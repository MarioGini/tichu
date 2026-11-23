import 'dart:math';

import 'package:tichu/agents/card_knowledge.dart';
import 'package:tichu/agents/endgame_solver.dart';
import 'package:tichu/agents/nn/nn_play_selection_strategy.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/agent_decisions.dart';
import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// Settings of the decision-time endgame search (see [EndgameSearcher]).
class EndgameSearch {
  /// Re-dealt worlds per searched decision.
  final int worlds;

  /// Search only decisions with at most this many cards in hand.
  final int maxCards;

  /// Required mean advantage (round points) over the policy's move.
  final double margin;

  /// At most this many actions are rolled out: the policy's move, pass,
  /// and the plays with the highest Q.
  final int maxActions;

  /// Solve one-on-one endgames exactly ([OneOnOneSolver]) at any hand size;
  /// falls back to the world search when the tree exceeds [solveBudget].
  final bool solveOneOnOne;
  final int solveBudget;

  /// Solve only when the two hands hold at most this many cards together.
  final int solveMaxCards;

  const EndgameSearch({
    this.worlds = 8,
    this.maxCards = 5,
    this.margin = 10,
    this.maxActions = 7,
    this.solveOneOnOne = false,
    this.solveBudget = 20000,
    this.solveMaxCards = 10,
  });

  @override
  String toString() =>
      'EndgameSearch(worlds: $worlds, maxCards: $maxCards, '
      'margin: $margin, maxActions: $maxActions, '
      'solveOneOnOne: $solveOneOnOne, solveBudget: $solveBudget)';
}

/// The decision rule: index of the action to play given rollout values
/// `values[world][action]` and the policy's choice [chosen].
///
/// Deviates only to an action that is no worse than [chosen] in every
/// world and better on average by more than [margin]; among those the one
/// with the highest mean advantage. Null values (not rolled out, stuck)
/// make an action ineligible; a world where [chosen] is null keeps
/// [chosen].
int pickEndgameAction(
  final List<List<double?>> values,
  final int chosen,
  final double margin,
) {
  if (values.isEmpty) return chosen;
  final count = values.first.length;
  var best = chosen;
  var bestAdvantage = margin;
  for (var a = 0; a < count; a++) {
    if (a == chosen) continue;
    var sum = 0.0;
    var ok = true;
    for (final world in values) {
      final va = world[a];
      final vc = world[chosen];
      if (va == null || vc == null || va < vc) {
        ok = false;
        break;
      }
      sum += va - vc;
    }
    if (!ok) continue;
    final advantage = sum / values.length;
    if (advantage > bestAdvantage) {
      bestAdvantage = advantage;
      best = a;
    }
  }
  return best;
}

/// A copy of [state] in which the cards [actorId] cannot see are dealt
/// anew: it keeps the actor's hand, the cards played, every hand size, and
/// the cards the actor passed in this round's schupf that the receiver
/// still holds; the other unseen cards are dealt uniformly at random.
///
/// With [canonicalPool] the unseen cards are put in a fixed order before
/// shuffling, so the world depends only on [random] and what the actor
/// knows (not on where the cards really are).
GameEngineState redealWorld(
  final GameEngineState state,
  final String actorId,
  final Random random, {
  final bool canonicalPool = true,
}) {
  final world = state.copy();
  final actor = world.players.firstWhere((final p) => p.id == actorId);
  String idAt(final int offset) => world.players
      .firstWhere((final p) => p.seat == (actor.seat + offset) % 4)
      .id;
  final pass = world.completedSchupfSelections[actorId];
  final pinned = <String, List<Card>>{};
  if (pass != null) {
    for (final (offset, card) in [
      (1, pass.toLeft),
      (2, pass.toPartner),
      (3, pass.toRight),
    ]) {
      final id = idAt(offset);
      final hand = world.hands[id] ?? const <Card>[];
      final i = hand.indexWhere(
        (final c) => c.face == card.face && c.color == card.color,
      );
      if (i >= 0) (pinned[id] ??= []).add(hand[i]);
    }
  }
  final others = [
    for (final p in world.players)
      if (p.id != actorId && (world.hands[p.id]?.isNotEmpty ?? false)) p.id,
  ];
  final pool = <Card>[];
  for (final id in others) {
    final keep = pinned[id] ?? const <Card>[];
    for (final c in world.hands[id]!) {
      if (!keep.any((final k) => identical(k, c))) pool.add(c);
    }
  }
  if (canonicalPool) {
    pool.sort((final a, final b) => cardSlot(a).compareTo(cardSlot(b)));
  }
  pool.shuffle(random);
  var next = 0;
  for (final id in others) {
    final size = world.hands[id]!.length;
    final keep = pinned[id] ?? const <Card>[];
    final hand = [...keep];
    while (hand.length < size) {
      hand.add(pool[next++]);
    }
    world.hands[id] = hand;
  }
  return world;
}

/// Play [fork] to the end of the round with [agents]; returns team one's
/// round points minus team two's, or null when the playout got stuck.
Future<int?> playOutRound(
  final GameEngine engine,
  final GameEngineState fork,
  final Map<String, PlayerAgent> agents,
) async {
  for (var steps = 0; steps < 5000; steps++) {
    final score = fork.scoreTracker.state;
    if (score.roundComplete) return score.teamOneRound - score.teamTwoRound;
    final request = AgentDecisions.next(engine, fork);
    if (request == null) return null;
    final snap = engine.buildSnapshot(fork);
    GameAction? action;
    try {
      action = await AgentDecisions.resolve(
        request,
        agents[request.playerId]!,
        snap,
        fork,
      );
      // Agents signal "no legal action" with StateError.
      // ignore: avoid_catching_errors
    } on StateError {
      return null;
    }
    if (action == null) continue;
    engine.applyAction(fork, action);
  }
  return null;
}

/// Decision-time endgame search, run by a driver that owns the game state
/// (the headless simulator, the app's `AiTurnRunner`).
///
/// For an on-turn play decision of a [SmartAiAgent] with
/// [SmartAiAgent.endgameSearch] set, at most `maxCards` cards in hand, two
/// or more actions and no finishing move, it rolls out every action
/// (capped) in `worlds` re-deals of the unseen cards ([redealWorld]) with
/// fresh bots from [rolloutAgent] playing all four seats to the end of the
/// round, and switches from the policy's move to another one by
/// [pickEndgameAction].
///
/// The rollouts call the agents directly (never the searcher), so the
/// rollout bots play plain and the search cannot recurse. The worlds use a
/// Random seeded from what the decider knows, so the search is
/// deterministic.
class EndgameSearcher {
  /// Fresh agents for the rollouts, by player id and seat.
  final PlayerAgent Function(String playerId, int seat) rolloutAgent;

  /// Yield to the event loop between rollouts (keeps the app's UI
  /// responsive while a bot thinks).
  final bool yieldBetweenRollouts;

  /// Decisions searched, moves changed, and time spent searching.
  int searches = 0;
  int switches = 0;
  int rollouts = 0;

  /// One-on-one endgames solved exactly, moves changed by the solver, and
  /// solver give-ups (tree too large).
  int solves = 0;
  int solveSwitches = 0;
  int solveGiveUps = 0;
  final Map<int, OneOnOneSolver> _solvers = {};
  final Stopwatch stopwatch = Stopwatch();

  EndgameSearcher({
    required this.rolloutAgent,
    this.yieldBetweenRollouts = false,
  });

  /// The action to play instead of [chosen] (which [agent] picked in
  /// [state]); [chosen] itself when the search does not apply or finds
  /// nothing clearly better.
  Future<GameAction> refine({
    required final GameEngine engine,
    required final GameEngineState state,
    required final PlayerAgent agent,
    required final GameAction chosen,
  }) async {
    if (agent is! SmartAiAgent) return chosen;
    final config = agent.endgameSearch;
    if (config == null || config.worlds < 1) return chosen;
    if (chosen is! PlayTurnAction && chosen is! PassAction) return chosen;
    final playerId = agent.playerId;
    if (chosen.playerId != playerId) return chosen;
    final current = state.players[state.currentPlayerIndex];
    if (current.id != playerId) return chosen;
    if (config.solveOneOnOne &&
        OneOnOneSolver.applies(
          state,
          playerId,
          maxCards: config.solveMaxCards,
        )) {
      stopwatch.start();
      try {
        final solver = _solvers[current.seat % 2] ??= OneOnOneSolver(
          engine: engine,
          agentFor: rolloutAgent,
          nodeBudget: config.solveBudget,
        );
        final solved = await solver.solve(state, playerId);
        if (solved != null) {
          solves++;
          if (!_sameAction(solved.action, chosen)) {
            solveSwitches++;
            return solved.action;
          }
          return chosen;
        }
        solveGiveUps++;
      } finally {
        stopwatch.stop();
      }
    }
    final hand = state.hands[playerId] ?? const <Card>[];
    if (hand.isEmpty || hand.length > config.maxCards) return chosen;

    final snapshot = engine.buildSnapshot(state);
    final options = agent.searchableActions(snapshot);
    if (options == null) return chosen;
    final turns = options.turns;
    final count = turns.length + (options.canPass ? 1 : 0);
    if (count < 2) return chosen;

    var chosenIndex = -1;
    if (chosen is PassAction) {
      if (options.canPass) chosenIndex = turns.length;
    } else if (chosen is PlayTurnAction) {
      final key = slotKey(chosen.cards);
      for (var i = 0; i < turns.length && chosenIndex < 0; i++) {
        if (slotKey(turns[i].cards) == key) chosenIndex = i;
      }
    }
    if (chosenIndex < 0) return chosen;

    stopwatch.start();
    try {
      searches++;
      final indices = _candidates(
        agent,
        snapshot,
        turns,
        canPass: options.canPass,
        chosenIndex: chosenIndex,
        maxActions: config.maxActions,
      );
      final actions = <int, GameAction>{
        for (final i in indices)
          i: i == chosenIndex
              ? chosen
              : i >= turns.length
              ? PassAction(playerId: playerId)
              : agent.playActionFor(snapshot, turns[i]),
      };
      final team = current.seat % 2;
      final random = Random(searchSeed(state, playerId));
      final values = <List<double?>>[];
      for (var w = 0; w < config.worlds; w++) {
        final world = redealWorld(state, playerId, random);
        final row = List<double?>.filled(count, null);
        for (final i in indices) {
          final fork = world.copy();
          final agents = {
            for (final p in fork.players) p.id: rolloutAgent(p.id, p.seat),
          };
          final action = actions[i]!;
          try {
            engine.applyAction(fork, _copyAction(action));
            // The engine signals an illegal action with StateError.
            // ignore: avoid_catching_errors
          } on StateError {
            continue;
          }
          rollouts++;
          final diff = await playOutRound(engine, fork, agents);
          if (diff != null) row[i] = (team == 0 ? diff : -diff).toDouble();
          if (yieldBetweenRollouts) await Future<void>.delayed(Duration.zero);
        }
        values.add(row);
      }
      final pick = pickEndgameAction(values, chosenIndex, config.margin);
      if (pick == chosenIndex) return chosen;
      switches++;
      return actions[pick]!;
    } finally {
      stopwatch.stop();
    }
  }

  /// Indices of the actions to roll out: all of them, or (above
  /// [maxActions]) the policy's move, pass, and the plays with the
  /// highest Q.
  static List<int> _candidates(
    final SmartAiAgent agent,
    final GameSnapshot snapshot,
    final List<TichuTurn> turns, {
    required final bool canPass,
    required final int chosenIndex,
    required final int maxActions,
  }) {
    final count = turns.length + (canPass ? 1 : 0);
    final all = [for (var i = 0; i < count; i++) i];
    if (count <= maxActions) return all;
    final keep = <int>{chosenIndex, if (canPass) turns.length};
    final strategy = agent.playSelectionStrategy;
    final order = [for (var i = 0; i < turns.length; i++) i];
    if (strategy is NnPlaySelectionStrategy) {
      final q = strategy.qValues(snapshot, turns);
      order.sort((final a, final b) => q[b].compareTo(q[a]));
    }
    for (final i in order) {
      if (keep.length >= maxActions) break;
      keep.add(i);
    }
    return keep.toList()..sort();
  }

  /// Seed for the worlds of a decision, from what [actorId] knows: their
  /// hand, the round's public record, hand sizes and the score. 30-bit
  /// arithmetic, so the web build (doubles) gives the same seed.
  static int searchSeed(final GameEngineState state, final String actorId) {
    var h = 17;
    void mix(final int x) => h = (h * 31 + x + 1) & 0x3FFFFFFF;
    final hand = [
      for (final c in state.hands[actorId] ?? const <Card>[]) cardSlot(c),
    ]..sort();
    hand.forEach(mix);
    mix(state.roundLog.length);
    for (final entry in state.roundLog) {
      mix(entry.cards.length);
      for (final c in entry.cards) {
        mix(cardSlot(c));
      }
    }
    for (final p in state.players) {
      mix(p.seat);
      mix(state.hands[p.id]?.length ?? 0);
    }
    final score = state.scoreTracker.state;
    mix(score.roundNumber);
    mix(score.teamOneTotal & 0xFFFF);
    mix(score.teamTwoTotal & 0xFFFF);
    return h;
  }

  /// Order-independent key of a set of cards.
  static String slotKey(final List<Card> cards) {
    final slots = [for (final c in cards) cardSlot(c)]..sort();
    return slots.join(',');
  }

  /// The Dragon gift to play instead of [chosen] (the rule's choice of
  /// [agent]): the solver's in a one-on-one endgame, else [chosen]. Who
  /// gets the trick matters there: the last player's tricks go to the
  /// first player out.
  Future<GameAction> refineDragonGift({
    required final GameEngine engine,
    required final GameEngineState state,
    required final PlayerAgent agent,
    required final GiveDragonAction chosen,
  }) async {
    if (agent is! SmartAiAgent) return chosen;
    final config = agent.endgameSearch;
    if (config == null || !config.solveOneOnOne) return chosen;
    final playerId = agent.playerId;
    if (state.pendingDragonGiveBy != playerId ||
        !OneOnOneSolver.applies(
          state,
          playerId,
          maxCards: config.solveMaxCards,
          toMove: false,
        )) {
      return chosen;
    }
    stopwatch.start();
    try {
      final current = state.players.firstWhere((final p) => p.id == playerId);
      final solver = _solvers[current.seat % 2] ??= OneOnOneSolver(
        engine: engine,
        agentFor: rolloutAgent,
        nodeBudget: config.solveBudget,
      );
      final solved = await solver.solve(state, playerId);
      if (solved == null) {
        solveGiveUps++;
        return chosen;
      }
      solves++;
      if (_sameAction(solved.action, chosen)) return chosen;
      solveSwitches++;
      return solved.action;
    } finally {
      stopwatch.stop();
    }
  }

  static bool _sameAction(final GameAction a, final GameAction b) {
    if (a is GiveDragonAction && b is GiveDragonAction) {
      return a.targetPlayerId == b.targetPlayerId;
    }
    if (a is PassAction && b is PassAction) return true;
    if (a is PlayTurnAction && b is PlayTurnAction) {
      return slotKey(a.cards) == slotKey(b.cards);
    }
    return false;
  }

  static GameAction _copyAction(final GameAction action) =>
      action is PlayTurnAction
      ? PlayTurnAction(
          playerId: action.playerId,
          cards: List<Card>.from(action.cards),
          inputWish: action.inputWish,
        )
      : action;
}
