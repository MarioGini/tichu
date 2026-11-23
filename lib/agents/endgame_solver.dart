import 'package:tichu/agents/card_knowledge.dart';
import 'package:tichu/agents/legal_play_guard.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/agent_decisions.dart';
import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/turn/move_generator.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// Exact solver for the one-on-one endgame.
///
/// Once two players are out and the round goes on (they were on different
/// teams), one player of each team is left. The other player's hand is
/// then exactly the set of cards the decider cannot see (everything else is
/// played or in the decider's hand), so the position is one of perfect
/// information and can be solved: a memoised minimax over every legal play,
/// pass and Dragon gift of both players, scored by the engine's own round
/// scoring (the last player's hand to the opponents, their tricks to the
/// first player out). The decider's team maximises its round points minus
/// the opponents'.
///
/// The rollouts of the endgame search play these positions with the nets,
/// which can misplay even with all cards known; the solver plays them
/// perfectly. It gives up (returns null) when the tree exceeds [nodeBudget]
/// distinct positions.
class OneOnOneSolver {
  final GameEngine engine;

  /// Agents for the other decisions of the line (only the Mah Jong wish is
  /// taken from them: [SmartAiAgent.playActionFor]).
  final PlayerAgent Function(String playerId, int seat) agentFor;

  /// Distinct positions searched before giving up.
  final int nodeBudget;

  /// Reuse solved positions (off only to check the memo key in tests).
  final bool memoize;

  int nodes = 0;
  final Map<String, int> _memo = {};
  final Map<String, SmartAiAgent?> _agents = {};
  late int _team;

  OneOnOneSolver({
    required this.engine,
    required this.agentFor,
    this.nodeBudget = 20000,
    this.memoize = true,
  });

  /// Whether [state] is a one-on-one endgame with [playerId] to move and at
  /// most [maxCards] cards left in the two hands together.
  static bool applies(
    final GameEngineState state,
    final String playerId, {
    final int maxCards = 28,
  }) {
    final active = [
      for (final p in state.players)
        if (state.hands[p.id]?.isNotEmpty ?? false) p,
    ];
    if (active.length != 2) return false;
    if (active[0].seat % 2 == active[1].seat % 2) return false;
    final cards = active.fold<int>(
      0,
      (final n, final p) => n + state.hands[p.id]!.length,
    );
    if (cards > maxCards) return false;
    return state.players[state.currentPlayerIndex].id == playerId;
  }

  /// Solved positions stay valid for the rest of the round: keep the memo
  /// while the same team decides in the same round (later decisions of the
  /// endgame are then mostly lookups).
  String? _memoOwner;

  /// The best action for [playerId] in [state] and its exact value for
  /// [playerId]'s team (round points minus the opponents'), or null when
  /// the solver does not apply or the tree is too large.
  Future<({GameAction action, int value})?> solve(
    final GameEngineState state,
    final String playerId,
  ) async {
    if (!applies(state, playerId)) return null;
    _team = state.players.firstWhere((final p) => p.id == playerId).seat % 2;
    nodes = 0;
    final owner =
        '${state.gameId}:${state.scoreTracker.state.roundNumber}:$_team';
    if (owner != _memoOwner) {
      _memo.clear();
      _memoOwner = owner;
    }
    try {
      final options = _options(state, playerId);
      if (options.isEmpty) return null;
      GameAction? best;
      var bestValue = -1 << 30;
      for (final action in options) {
        final child = state.copy();
        engine.applyAction(child, _copy(action));
        final v = await _value(child);
        if (v > bestValue) {
          bestValue = v;
          best = action;
        }
      }
      return best == null ? null : (action: best, value: bestValue);
    } on _BudgetExceeded {
      return null;
      // The engine signals an illegal action with StateError.
      // ignore: avoid_catching_errors
    } on StateError {
      return null;
    }
  }

  /// Exact values of [actions] (for [playerId] in [state]); null entries
  /// when the tree is too large. For analysis and tests.
  Future<List<int?>> values(
    final GameEngineState state,
    final String playerId,
    final List<GameAction> actions,
  ) async {
    _team = state.players.firstWhere((final p) => p.id == playerId).seat % 2;
    final out = <int?>[];
    for (final action in actions) {
      nodes = 0;
      try {
        final child = state.copy();
        engine.applyAction(child, _copy(action));
        out.add(await _value(child));
      } on _BudgetExceeded {
        out.add(null);
        // The engine signals an illegal action with StateError.
        // ignore: avoid_catching_errors
      } on StateError {
        out.add(null);
      }
    }
    return out;
  }

  Future<int> _value(final GameEngineState state) async {
    final score = state.scoreTracker.state;
    if (score.roundComplete) {
      final diff = score.teamOneRound - score.teamTwoRound;
      return _team == 0 ? diff : -diff;
    }
    final key = memoize ? _key(state) : '';
    final hit = memoize ? _memo[key] : null;
    if (hit != null) return hit;
    if (++nodes > nodeBudget) throw _BudgetExceeded();

    final request = AgentDecisions.next(engine, state);
    if (request == null) throw _BudgetExceeded();
    final List<GameAction> options;
    switch (request) {
      case TurnRequest(:final playerId):
        options = _options(state, playerId);
      case DragonGiveRequest(:final playerId, :final opponentIds):
        options = [
          for (final id in opponentIds)
            GiveDragonAction(playerId: playerId, targetPlayerId: id),
        ];
      default:
        final agent = agentFor(
          request.playerId,
          state.players.firstWhere((final p) => p.id == request.playerId).seat,
        );
        final action = await AgentDecisions.resolve(
          request,
          agent,
          engine.buildSnapshot(state),
          state,
        );
        final child = state.copy();
        if (action != null) engine.applyAction(child, action);
        final v = await _value(child);
        if (memoize) _memo[key] = v;
        return v;
    }
    if (options.isEmpty) throw _BudgetExceeded();
    final mover = state.players.firstWhere(
      (final p) => p.id == request.playerId,
    );
    final maximise = mover.seat % 2 == _team;
    var best = maximise ? -1 << 30 : 1 << 30;
    for (final action in options) {
      final child = state.copy();
      engine.applyAction(child, _copy(action));
      final v = await _value(child);
      if (maximise ? v > best : v < best) best = v;
    }
    if (memoize) _memo[key] = best;
    return best;
  }

  /// Every legal play (wish-filtered) and the pass when legal.
  List<GameAction> _options(
    final GameEngineState state,
    final String playerId,
  ) {
    final snapshot = engine.buildSnapshot(state);
    final hand = List<Card>.from(state.hands[playerId] ?? const <Card>[]);
    final deck = snapshot.deck;
    final turns = LegalPlayGuard.filterMoveGeneratorTurns(
      deck: deck,
      hand: hand,
      moveGeneratorTurns: generateLegalTurns(deck, hand),
    );
    final agent = _agents.putIfAbsent(playerId, () {
      final seat = state.players.firstWhere((final p) => p.id == playerId).seat;
      final a = agentFor(playerId, seat);
      return a is SmartAiAgent ? a : null;
    });
    return [
      for (final t in turns)
        if (agent != null)
          agent.playActionFor(snapshot, t)
        else
          PlayTurnAction(playerId: playerId, cards: t.cards),
      if (LegalPlayGuard.canPass(deck: deck, hand: hand))
        PassAction(playerId: playerId),
    ];
  }

  String _key(final GameEngineState s) {
    final b = StringBuffer()
      ..write(s.currentPlayerIndex)
      ..write('|')
      ..write(s.phase.index)
      ..write('|');
    for (final p in s.players) {
      final slots = [
        for (final c in s.hands[p.id] ?? const <Card>[]) cardSlot(c),
      ]..sort();
      b
        ..write(slots.join(','))
        ..write(';')
        ..write(s.scoreTracker.state.playerRoundPoints[p.id] ?? 0)
        ..write('/');
    }
    final deck = s.deck;
    final trick = [for (final c in deck.turn.cards) cardSlot(c)]..sort();
    final pile = [for (final c in s.currentTrickCards) cardSlot(c)]..sort();
    b
      ..write('|${deck.turn.type.index}:${trick.join(',')}')
      ..write('|${deck.wish.index}|${deck.currentWinner}')
      ..write('|${s.consecutivePasses}|${pile.join(',')}')
      ..write('|${s.lastPlayedBy}|${s.lastPlayedTurn?.type.index}')
      ..write(
        ':${[for (final c in s.lastPlayedTurn?.cards ?? const <Card>[]) cardSlot(c)].join(',')}',
      )
      ..write(
        '|${s.pendingDragonGiveBy}|${s.pendingDragonGiveTargets.join(',')}',
      )
      ..write('|${s.finishedPlayers.join(',')}')
      ..write('|${s.scoreTracker.state.finishOrder.join(',')}');
    return b.toString();
  }

  static GameAction _copy(final GameAction action) => action is PlayTurnAction
      ? PlayTurnAction(
          playerId: action.playerId,
          cards: List<Card>.from(action.cards),
          inputWish: action.inputWish,
        )
      : action;
}

class _BudgetExceeded implements Exception {}
