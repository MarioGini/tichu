import 'dart:math';

import 'package:tichu/agents/mcts/belief_tracker.dart';
import 'package:tichu/agents/mcts/hand_sampler.dart';
import 'package:tichu/agents/nn/feature_encoder.dart';
import 'package:tichu/agents/nn/mlp.dart';
import 'package:tichu/agents/play_selection_strategy.dart';
import 'package:tichu/game/engine_state.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';
import 'package:tichu/game/turn/move_generator.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/wish_logic.dart';

/// Result of a single MCTS rollout from one determinized world.
class RolloutResult {
  /// Score delta from the perspective of the searching player's team.
  /// Positive = good for us.
  final double value;

  const RolloutResult(this.value);
}

/// Builds a throwaway [GameEngineState] from a snapshot + sampled hands,
/// then plays forward to round-end using fast heuristic rollout policy.
class RolloutSimulator {
  final Random _random;
  final DefaultPlaySelectionStrategy _rolloutPolicy;
  static const _maxRolloutSteps = 500;

  /// Optional value network for leaf evaluation. When provided, positions
  /// are evaluated by the network after [earlyStopDepth] steps instead of
  /// rolling out to completion. This is the AlphaZero-style hybrid approach.
  final Mlp? valueNetwork;
  final double valueNetworkMean;
  final double valueNetworkStd;
  final int earlyStopDepth;

  RolloutSimulator({
    final Random? random,
    this.valueNetwork,
    this.valueNetworkMean = 0.0,
    this.valueNetworkStd = 1.0,
    this.earlyStopDepth = 20,
  }) : _random = random ?? Random(),
       _rolloutPolicy = const DefaultPlaySelectionStrategy();

  /// Run a single rollout:
  /// 1. Build a fresh engine state matching the snapshot.
  /// 2. Apply [firstAction] (the move we're evaluating).
  /// 3. Play to round completion with heuristic agents.
  /// 4. Return the score delta for [myTeam].
  RolloutResult rollout({
    required final GameSnapshot snapshot,
    required final Map<String, List<Card>> sampledHands,
    required final GameAction firstAction,
    required final int myTeam,
  }) {
    final engine = GameEngineImpl(random: _random);
    final state = _buildState(snapshot: snapshot, sampledHands: sampledHands);

    // Apply the candidate action.
    try {
      engine.applyAction(state, firstAction);
    } on StateError {
      // Illegal action in this determinization — return neutral.
      return const RolloutResult(0);
    }

    // Play forward until round completes.
    var steps = 0;
    while (!state.scoreTracker.state.roundComplete &&
        steps < _maxRolloutSteps) {
      // Value network early stop: after earlyStopDepth steps, evaluate
      // the position with the network instead of continuing rollout.
      if (valueNetwork != null && steps >= earlyStopDepth) {
        final snap = engine.buildSnapshot(state);
        return _evaluateWithNetwork(snap, myTeam);
      }

      final snap = engine.buildSnapshot(state);
      final action = _selectRolloutAction(
        engine: engine,
        state: state,
        snapshot: snap,
      );
      if (action == null) break;

      try {
        engine.applyAction(state, action);
      } on StateError {
        break;
      }
      steps++;
    }

    // Evaluate outcome.
    final finalScore = state.scoreTracker.state;
    final myRound = myTeam == 0
        ? finalScore.teamOneRound
        : finalScore.teamTwoRound;
    final oppRound = myTeam == 0
        ? finalScore.teamTwoRound
        : finalScore.teamOneRound;

    return RolloutResult((myRound - oppRound).toDouble());
  }

  GameEngineState _buildState({
    required final GameSnapshot snapshot,
    required final Map<String, List<Card>> sampledHands,
  }) {
    final tracker = LocalScoreTracker.forRollout(
      scoreState: snapshot.scoreState,
      players: snapshot.players,
    );

    final currentPlayerIndex = snapshot.players.indexWhere(
      (final p) => p.id == snapshot.currentPlayerId,
    );

    final state = GameEngineState(
      gameId: 'rollout',
      players: snapshot.players,
      hands: {
        for (final entry in sampledHands.entries)
          entry.key: List<Card>.from(entry.value),
      },
      deck: DeckState(snapshot.deck.turn, snapshot.deck.wish)
        ..currentWinner = snapshot.deck.currentWinner
        ..cardStack = List<Card>.from(snapshot.deck.cardStack),
      currentPlayerIndex: currentPlayerIndex >= 0 ? currentPlayerIndex : 0,
      scoreTracker: tracker,
      reservedHands: const {},
      phase: snapshot.phase,
    );

    state.consecutivePasses = snapshot.consecutivePasses;
    state.lastPlayedBy = snapshot.lastPlayedBy;
    state.lastPlayedTurn = snapshot.lastPlayedTurn;
    state.lastDragonGiveBy = snapshot.lastDragonGiveBy;
    state.lastDragonGiveTo = snapshot.lastDragonGiveTo;

    if (snapshot.pendingDragonGiveBy != null) {
      state.pendingDragonGiveBy = snapshot.pendingDragonGiveBy;
      state.pendingDragonGiveTargets.addAll(snapshot.pendingDragonGiveTargets);
    }

    // Mark finished players.
    for (final playerId in snapshot.scoreState.finishOrder) {
      state.finishedPlayers.add(playerId);
    }

    // Track who has played cards this round (for tichu call eligibility).
    for (final player in snapshot.players) {
      if (snapshot.hands[player.id] != null &&
          snapshot.hands[player.id]!.length < 14) {
        state.playersWhoPlayedCardsThisRound.add(player.id);
      }
    }

    return state;
  }

  /// Evaluate a position using the value network.
  RolloutResult _evaluateWithNetwork(
    final GameSnapshot snapshot,
    final int myTeam,
  ) {
    final playerId = snapshot.currentPlayerId;
    final stateFeatures = encodeStateFeatures(
      snapshot: snapshot,
      playerId: playerId,
    );
    final dummyAction = List<double>.filled(actionFeatureCount, 0.0);
    final input = [...stateFeatures, ...dummyAction];

    var value = valueNetwork!.predict(input);
    // Denormalize.
    value = value * valueNetworkStd + valueNetworkMean;

    // Flip sign if we're evaluating from the opponent's perspective.
    final evalTeam = snapshot.players
        .firstWhere(
          (final p) => p.id == playerId,
          orElse: () => snapshot.players.first,
        )
        .seat
        .isEven
        ? 0
        : 1;
    if (evalTeam != myTeam) value = -value;

    return RolloutResult(value);
  }

  GameAction? _selectRolloutAction({
    required final GameEngineImpl engine,
    required final GameEngineState state,
    required final GameSnapshot snapshot,
  }) {
    // Handle schupf receipt acknowledgements.
    for (final player in state.players) {
      final receipts = state.schupfReceipts[player.id];
      if (receipts != null && receipts.isNotEmpty) {
        return AcknowledgeSchupfAction(playerId: player.id);
      }
    }

    // Grand tichu — always pass during rollouts.
    if (state.phase == GamePhase.grandTichu) {
      final current = state.players[state.currentPlayerIndex];
      if (!state.grandTichuDecisions.containsKey(current.id)) {
        return GrandTichuDecisionAction(playerId: current.id, call: false);
      }
      return null;
    }

    // Schupf — skip for rollouts (shouldn't happen mid-round).
    if (state.phase == GamePhase.schupf) {
      return null;
    }

    // Dragon give.
    if (state.pendingDragonGiveBy != null) {
      final winnerId = state.pendingDragonGiveBy!;
      final opponentIds = engine.opponentIds(state, winnerId);
      if (opponentIds.isEmpty) return null;
      return GiveDragonAction(
        playerId: winnerId,
        targetPlayerId: opponentIds.first,
      );
    }

    // Play phase — use fast sync heuristic.
    final currentPlayer = state.players[state.currentPlayerIndex];
    final playerId = currentPlayer.id;
    final hand = state.hands[playerId] ?? const <Card>[];
    if (hand.isEmpty) {
      return PassAction(playerId: playerId);
    }

    final legalTurns = generateLegalTurns(snapshot.deck, List<Card>.from(hand));

    if (legalTurns.isEmpty) {
      final canPass =
          snapshot.deck.turn.type != TurnType.empty &&
          snapshot.deck.turn.type != TurnType.none &&
          !mahJong(snapshot.deck, TichuTurn(TurnType.none, const []), hand);
      if (canPass) return PassAction(playerId: playerId);
      return null;
    }

    // Pick the best play using the sync heuristic scorer.
    final selected = _rolloutPolicy.selectPlay(
      snapshot,
      legalTurns,
      snapshot.deck,
      List<Card>.from(hand),
    );

    return PlayTurnAction(
      playerId: playerId,
      cards: List<Card>.from(selected.cards),
      inputWish: CardFace.none,
    );
  }
}

/// Information Set MCTS using determinization (PIMC approach).
///
/// For each candidate move at the root:
///   1. Sample a plausible opponent hand assignment (determinization).
///   2. Play the candidate move, then run a heuristic rollout to round-end.
///   3. Record the outcome.
///
/// After [numRollouts] total rollouts, pick the move with the highest
/// average score delta.
///
/// This is the same approach used in world-class Bridge AI (GIB, Wbridge5)
/// and competitive Skat/Hearts programs.
class MctsSearch {
  final int numDeterminizations;
  final int rolloutsPerDeterminization;
  final HandSampler _sampler;
  final RolloutSimulator _simulator;

  MctsSearch({
    this.numDeterminizations = 20,
    this.rolloutsPerDeterminization = 1,
    final Mlp? valueNetwork,
    final double valueNetworkMean = 0.0,
    final double valueNetworkStd = 1.0,
    final int valueNetworkEarlyStopDepth = 20,
    final Random? random,
  }) : _sampler = HandSampler(random: random),
       _simulator = RolloutSimulator(
         random: random,
         valueNetwork: valueNetwork,
         valueNetworkMean: valueNetworkMean,
         valueNetworkStd: valueNetworkStd,
         earlyStopDepth: valueNetworkEarlyStopDepth,
       );

  /// Search for the best action among [candidates] from [snapshot].
  ///
  /// If [beliefTracker] is provided, sampled hands are constrained by
  /// observed pass behavior.
  GameAction? search({
    required final GameSnapshot snapshot,
    required final String playerId,
    required final List<GameAction> candidates,
    final BeliefTracker? beliefTracker,
  }) {
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.first;

    final myTeam = _teamForPlayer(snapshot, playerId);
    final stats = {
      for (var i = 0; i < candidates.length; i++) i: _ActionStats(),
    };

    for (var d = 0; d < numDeterminizations; d++) {
      final sampledHands = _sampler.sampleHands(
        snapshot: snapshot,
        myPlayerId: playerId,
        beliefTracker: beliefTracker,
      );

      for (var r = 0; r < rolloutsPerDeterminization; r++) {
        for (var i = 0; i < candidates.length; i++) {
          final result = _simulator.rollout(
            snapshot: snapshot,
            sampledHands: sampledHands,
            firstAction: candidates[i],
            myTeam: myTeam,
          );
          stats[i]!.add(result.value);
        }
      }
    }

    // Pick the action with the highest mean value.
    var bestIdx = 0;
    var bestMean = double.negativeInfinity;
    for (var i = 0; i < candidates.length; i++) {
      final mean = stats[i]!.mean;
      if (mean > bestMean) {
        bestMean = mean;
        bestIdx = i;
      }
    }

    return candidates[bestIdx];
  }

  int _teamForPlayer(final GameSnapshot snapshot, final String playerId) {
    final player = snapshot.players.firstWhere(
      (final p) => p.id == playerId,
      orElse: () => snapshot.players.first,
    );
    return player.seat.isEven ? 0 : 1;
  }
}

class _ActionStats {
  double _sum = 0;
  int _count = 0;

  void add(final double value) {
    _sum += value;
    _count++;
  }

  double get mean => _count == 0 ? 0 : _sum / _count;
}
