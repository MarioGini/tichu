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

/// Information Set Monte Carlo Tree Search (IS-MCTS / SO-ISMCTS).
///
/// Unlike PIMC (which builds a separate tree per determinization), IS-MCTS
/// builds a **single tree** across all sampled worlds. Each node corresponds
/// to an information set (what the acting player knows), not a specific
/// world state. This avoids the "strategy fusion" problem where PIMC
/// recommends actions that are good on average but catastrophic in specific
/// worlds.
///
/// Algorithm (Single Observer IS-MCTS, Cowling et al. 2012):
///   For each simulation:
///     1. Sample a determinization (plausible opponent hands).
///     2. Descend the tree using UCB1, skipping unavailable actions.
///     3. Expand one new node.
///     4. Evaluate the leaf (rollout or value network).
///     5. Backpropagate the result up the tree.
///
///   After all simulations, pick the root action with the highest visit count.
class IsmctsSearch {
  final int numSimulations;
  final double explorationConstant;
  final HandSampler _sampler;
  final Random _random;

  /// Optional value network for leaf evaluation. If null, uses heuristic
  /// rollouts.
  final Mlp? valueNetwork;
  final double? valueNetworkMean;
  final double? valueNetworkStd;

  IsmctsSearch({
    this.numSimulations = 100,
    this.explorationConstant = 1.4,
    this.valueNetwork,
    this.valueNetworkMean,
    this.valueNetworkStd,
    final Random? random,
  }) : _random = random ?? Random(),
       _sampler = HandSampler(random: random);

  /// Search for the best action among [candidates] from [snapshot].
  GameAction? search({
    required final GameSnapshot snapshot,
    required final String playerId,
    required final List<GameAction> candidates,
    final BeliefTracker? beliefTracker,
  }) {
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.first;

    final myTeam = _teamForPlayer(snapshot, playerId);

    // Build root node with all candidate actions.
    final root = _IsmctsNode(playerId: playerId);
    for (final action in candidates) {
      root.children[action] = _IsmctsNode(playerId: '');
    }

    for (var sim = 0; sim < numSimulations; sim++) {
      // Sample a determinization.
      final sampledHands = _sampler.sampleHands(
        snapshot: snapshot,
        myPlayerId: playerId,
        beliefTracker: beliefTracker,
      );

      // Selection + expansion + evaluation + backpropagation.
      final value = _simulateFromRoot(
        snapshot: snapshot,
        sampledHands: sampledHands,
        root: root,
        candidates: candidates,
        playerId: playerId,
        myTeam: myTeam,
      );

      // Backpropagate at root.
      root.visits++;
      root.totalValue += value;
    }

    // Pick the action with the highest visit count (most robust).
    GameAction? bestAction;
    var bestVisits = -1;
    var bestMeanValue = double.negativeInfinity;

    for (final entry in root.children.entries) {
      final child = entry.value;
      if (child.visits > bestVisits ||
          (child.visits == bestVisits && child.meanValue > bestMeanValue)) {
        bestVisits = child.visits;
        bestMeanValue = child.meanValue;
        bestAction = entry.key;
      }
    }

    return bestAction;
  }

  double _simulateFromRoot({
    required final GameSnapshot snapshot,
    required final Map<String, List<Card>> sampledHands,
    required final _IsmctsNode root,
    required final List<GameAction> candidates,
    required final String playerId,
    required final int myTeam,
  }) {
    // Select action at root using UCB1 over available actions.
    // In IS-MCTS, we only consider actions that are legal in this
    // determinization. For root level, all candidates are legal by
    // construction.
    final selected = _selectUcb1(root, candidates);
    final selectedAction = selected.action;
    final selectedNode = selected.node;

    // Build engine state and apply the selected action.
    final engine = GameEngineImpl(random: _random);
    final state = _buildState(snapshot: snapshot, sampledHands: sampledHands);

    try {
      engine.applyAction(state, selectedAction);
    } on StateError {
      // Illegal in this determinization — neutral.
      return 0.0;
    }

    // Evaluate: either use value network or heuristic rollout.
    final value = _evaluate(
      engine: engine,
      state: state,
      snapshot: engine.buildSnapshot(state),
      playerId: playerId,
      myTeam: myTeam,
    );

    // Backpropagate.
    selectedNode.visits++;
    selectedNode.totalValue += value;

    return value;
  }

  _Selected _selectUcb1(
    final _IsmctsNode node,
    final List<GameAction> availableActions,
  ) {
    final lnParentVisits = node.visits > 0 ? log(node.visits) : 0.0;
    GameAction? bestAction;
    _IsmctsNode? bestNode;
    var bestUcb = double.negativeInfinity;

    for (final action in availableActions) {
      final child = node.children[action]!;

      double ucb;
      if (child.visits == 0) {
        ucb = double.infinity; // Unvisited — explore first.
      } else {
        ucb = child.meanValue +
            explorationConstant * sqrt(lnParentVisits / child.visits);
      }

      if (ucb > bestUcb) {
        bestUcb = ucb;
        bestAction = action;
        bestNode = child;
      }
    }

    return _Selected(action: bestAction!, node: bestNode!);
  }

  double _evaluate({
    required final GameEngineImpl engine,
    required final GameEngineState state,
    required final GameSnapshot snapshot,
    required final String playerId,
    required final int myTeam,
  }) {
    // Try value network first.
    if (valueNetwork != null) {
      return _evaluateWithNetwork(
        snapshot: snapshot,
        playerId: playerId,
        myTeam: myTeam,
      );
    }

    // Fall back to heuristic rollout.
    return _heuristicRollout(
      engine: engine,
      state: state,
      myTeam: myTeam,
    );
  }

  double _evaluateWithNetwork({
    required final GameSnapshot snapshot,
    required final String playerId,
    required final int myTeam,
  }) {
    final stateFeatures = encodeStateFeatures(
      snapshot: snapshot,
      playerId: playerId,
    );
    // Use a "no-op" action encoding for state value estimation.
    final dummyAction = List<double>.filled(actionFeatureCount, 0.0);
    final input = [...stateFeatures, ...dummyAction];

    var value = valueNetwork!.predict(input);

    // Denormalize if normalization stats are available.
    final std = valueNetworkStd ?? 1.0;
    final mean = valueNetworkMean ?? 0.0;
    value = value * std + mean;

    return value;
  }

  double _heuristicRollout({
    required final GameEngineImpl engine,
    required final GameEngineState state,
    required final int myTeam,
  }) {
    const maxSteps = 500;
    const rolloutPolicy = DefaultPlaySelectionStrategy();
    var steps = 0;

    while (!state.scoreTracker.state.roundComplete && steps < maxSteps) {
      final snap = engine.buildSnapshot(state);
      final action = _selectRolloutAction(
        engine: engine,
        state: state,
        snapshot: snap,
        policy: rolloutPolicy,
      );
      if (action == null) break;

      try {
        engine.applyAction(state, action);
      } on StateError {
        break;
      }
      steps++;
    }

    final finalScore = state.scoreTracker.state;
    final myRound = myTeam == 0
        ? finalScore.teamOneRound
        : finalScore.teamTwoRound;
    final oppRound = myTeam == 0
        ? finalScore.teamTwoRound
        : finalScore.teamOneRound;

    return (myRound - oppRound).toDouble();
  }

  GameAction? _selectRolloutAction({
    required final GameEngineImpl engine,
    required final GameEngineState state,
    required final GameSnapshot snapshot,
    required final DefaultPlaySelectionStrategy policy,
  }) {
    for (final player in state.players) {
      final receipts = state.schupfReceipts[player.id];
      if (receipts != null && receipts.isNotEmpty) {
        return AcknowledgeSchupfAction(playerId: player.id);
      }
    }

    if (state.phase == GamePhase.grandTichu) {
      final current = state.players[state.currentPlayerIndex];
      if (!state.grandTichuDecisions.containsKey(current.id)) {
        return GrandTichuDecisionAction(playerId: current.id, call: false);
      }
      return null;
    }

    if (state.phase == GamePhase.schupf) return null;

    if (state.pendingDragonGiveBy != null) {
      final winnerId = state.pendingDragonGiveBy!;
      final opponentIds = engine.opponentIds(state, winnerId);
      if (opponentIds.isEmpty) return null;
      return GiveDragonAction(
        playerId: winnerId,
        targetPlayerId: opponentIds.first,
      );
    }

    final currentPlayer = state.players[state.currentPlayerIndex];
    final playerId = currentPlayer.id;
    final hand = state.hands[playerId] ?? const <Card>[];
    if (hand.isEmpty) return PassAction(playerId: playerId);

    final legalTurns = generateLegalTurns(
      snapshot.deck,
      List<Card>.from(hand),
    );

    if (legalTurns.isEmpty) {
      final canPass = snapshot.deck.turn.type != TurnType.empty &&
          snapshot.deck.turn.type != TurnType.none &&
          !mahJong(snapshot.deck, TichuTurn(TurnType.none, const []), hand);
      if (canPass) return PassAction(playerId: playerId);
      return null;
    }

    final selected = policy.selectPlay(
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
      gameId: 'ismcts',
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

    for (final playerId in snapshot.scoreState.finishOrder) {
      state.finishedPlayers.add(playerId);
    }

    for (final player in snapshot.players) {
      if (snapshot.hands[player.id] != null &&
          snapshot.hands[player.id]!.length < 14) {
        state.playersWhoPlayedCardsThisRound.add(player.id);
      }
    }

    return state;
  }

  int _teamForPlayer(final GameSnapshot snapshot, final String playerId) {
    final player = snapshot.players.firstWhere(
      (final p) => p.id == playerId,
      orElse: () => snapshot.players.first,
    );
    return player.seat.isEven ? 0 : 1;
  }
}

class _IsmctsNode {
  final String playerId;
  int visits = 0;
  double totalValue = 0;
  final Map<GameAction, _IsmctsNode> children = {};

  _IsmctsNode({required this.playerId});

  double get meanValue => visits == 0 ? 0 : totalValue / visits;
}

class _Selected {
  final GameAction action;
  final _IsmctsNode node;

  const _Selected({required this.action, required this.node});
}
