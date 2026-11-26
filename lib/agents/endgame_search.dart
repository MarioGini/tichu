import 'dart:math';

import 'package:tichu/agents/card_knowledge.dart';
import 'package:tichu/agents/endgame_solver.dart';
import 'package:tichu/agents/nn/belief_model.dart';
import 'package:tichu/agents/nn/nn_play_selection_strategy.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/simulation.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/bomb_utils.dart';

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

  /// Re-deal the worlds with the searcher's card-location model
  /// ([EndgameSearcher.belief]) instead of uniformly.
  final bool beliefWorlds;

  /// A deviation must be strictly better than the policy's move in at
  /// least this many worlds. With 1, a single world with a large swing
  /// (90 points in 1 of 8 worlds is a mean of 11) could override the
  /// policy while every other world was a tie.
  final int minBetterWorlds;

  /// Sample the worlds in two strata, with and without a bomb in another
  /// player's hand, and weight them by the bomb's probability (estimated
  /// from [bombProbes] cheap re-deals). Without it a rare bomb shows up in
  /// 0, 1 or 2 of the [worlds] by chance and decides on that noise.
  final bool bombStrata;
  final int bombProbes;

  const EndgameSearch({
    this.worlds = 8,
    this.maxCards = 5,
    this.margin = 10,
    this.maxActions = 7,
    this.solveOneOnOne = false,
    this.solveBudget = 20000,
    this.solveMaxCards = 10,
    this.beliefWorlds = false,
    this.minBetterWorlds = 2,
    this.bombStrata = false,
    this.bombProbes = 256,
  });

  @override
  String toString() =>
      'EndgameSearch(worlds: $worlds, maxCards: $maxCards, '
      'margin: $margin, maxActions: $maxActions, '
      'solveOneOnOne: $solveOneOnOne, solveBudget: $solveBudget, '
      'minBetterWorlds: $minBetterWorlds, bombStrata: $bombStrata)';
}

/// The decision rule: index of the action to play given rollout values
/// `values[world][action]` and the policy's choice [chosen].
///
/// Deviates only to an action that is no worse than [chosen] in every
/// world, strictly better in at least [minBetterWorlds] of them (capped at
/// the number of worlds) and better on average by more than [margin];
/// among those the one with the highest mean advantage. Null values (not
/// rolled out, stuck) make an action ineligible; a world where [chosen] is
/// null keeps [chosen]. [weights] (summing to 1, one per world) weight the
/// mean; equal weights by default.
int pickEndgameAction(
  List<List<double?>> values,
  int chosen,
  double margin, {
  int minBetterWorlds = 1,
  List<double>? weights,
}) {
  if (values.isEmpty) return chosen;
  final needBetter = min(minBetterWorlds, values.length);
  final count = values.first.length;
  var best = chosen;
  var bestAdvantage = margin;
  for (var a = 0; a < count; a++) {
    if (a == chosen) continue;
    var sum = 0.0;
    var better = 0;
    var ok = true;
    for (var w = 0; w < values.length; w++) {
      final va = values[w][a];
      final vc = values[w][chosen];
      if (va == null || vc == null || va < vc) {
        ok = false;
        break;
      }
      if (va > vc) better++;
      sum += (va - vc) * (weights?[w] ?? 1 / values.length);
    }
    if (!ok || better < needBetter) continue;
    final advantage = sum;
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
///
/// With [holders] (`holders[slot][k]`, k = 0 left opponent, 1 partner,
/// 2 right opponent, from [BeliefModel]) each card goes to a player in
/// proportion to that probability times the room left in their hand,
/// instead of uniformly: the world reflects what the play revealed.
GameEngineState redealWorld(
  GameEngineState state,
  String actorId,
  Random random, {
  bool canonicalPool = true,
  List<List<double>>? holders,
}) {
  final world = state.copy();
  dealUnseen(
    state,
    actorId,
    random,
    canonicalPool: canonicalPool,
    holders: holders,
  ).forEach((id, hand) => world.hands[id] = hand);
  return world;
}

/// The hands of the other players in a re-deal of [state] as
/// [redealWorld] makes it, without copying the state.
Map<String, List<Card>> dealUnseen(
  GameEngineState state,
  String actorId,
  Random random, {
  bool canonicalPool = true,
  List<List<double>>? holders,
}) {
  final actor = state.players.firstWhere((p) => p.id == actorId);
  String idAt(int offset) =>
      state.players.firstWhere((p) => p.seat == (actor.seat + offset) % 4).id;
  final pass = state.completedSchupfSelections[actorId];
  final pinned = <String, List<Card>>{};
  if (pass != null) {
    for (final (offset, card) in [
      (1, pass.toLeft),
      (2, pass.toPartner),
      (3, pass.toRight),
    ]) {
      final id = idAt(offset);
      final hand = state.hands[id] ?? const <Card>[];
      final i = hand.indexWhere(
        (c) => c.face == card.face && c.color == card.color,
      );
      if (i >= 0) (pinned[id] ??= []).add(hand[i]);
    }
  }
  final others = [
    for (final p in state.players)
      if (p.id != actorId && (state.hands[p.id]?.isNotEmpty ?? false)) p.id,
  ];
  final pool = <Card>[];
  for (final id in others) {
    final keep = pinned[id] ?? const <Card>[];
    for (final c in state.hands[id]!) {
      if (!keep.any((k) => identical(k, c))) pool.add(c);
    }
  }
  if (canonicalPool) {
    pool.sort((a, b) => cardSlot(a).compareTo(cardSlot(b)));
  }
  pool.shuffle(random);
  if (holders != null) {
    final room = <String, int>{
      for (final id in others)
        id: state.hands[id]!.length - (pinned[id]?.length ?? 0),
    };
    final rel = <String, int>{idAt(1): 0, idAt(2): 1, idAt(3): 2};
    final dealt = <String, List<Card>>{
      for (final id in others) id: [...?pinned[id]],
    };
    for (final card in pool) {
      final slot = cardSlot(card);
      var total = 0.0;
      final w = <String, double>{};
      for (final id in others) {
        final r = room[id]!;
        if (r <= 0) continue;
        final p = slot >= 0 ? holders[slot][rel[id]!] : 1.0;
        // Room in the hand keeps the deal feasible; the belief tilts it.
        w[id] = (p + 1e-3) * r;
        total += w[id]!;
      }
      var x = random.nextDouble() * total;
      var pick = w.keys.last;
      for (final e in w.entries) {
        x -= e.value;
        if (x <= 0) {
          pick = e.key;
          break;
        }
      }
      dealt[pick]!.add(card);
      room[pick] = room[pick]! - 1;
    }
    return dealt;
  }
  var next = 0;
  final result = <String, List<Card>>{};
  for (final id in others) {
    final size = state.hands[id]!.length;
    final keep = pinned[id] ?? const <Card>[];
    final hand = [...keep];
    while (hand.length < size) {
      hand.add(pool[next++]);
    }
    result[id] = hand;
  }
  return result;
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

  /// Card-location model for [EndgameSearch.beliefWorlds].
  final BeliefModel? belief;

  EndgameSearcher({
    required this.rolloutAgent,
    this.yieldBetweenRollouts = false,
    this.belief,
  });

  /// The action to play instead of [chosen] (which [agent] picked in
  /// [state]); [chosen] itself when the search does not apply or finds
  /// nothing clearly better.
  Future<GameAction> refine({
    required GameEngineState state,
    required PlayerAgent agent,
    required GameAction chosen,
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

    final snapshot = simulationEngine.buildSnapshot(state);
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
      final holders = config.beliefWorlds && belief != null
          ? belief!.holderProbabilities(snapshot, playerId)
          : null;
      final (worlds, weights) = config.bombStrata
          ? _bombStrataWorlds(state, playerId, random, holders, config)
          : (
              [
                for (var w = 0; w < config.worlds; w++)
                  redealWorld(state, playerId, random, holders: holders),
              ],
              null,
            );
      for (final world in worlds) {
        final row = List<double?>.filled(count, null);
        for (final i in indices) {
          final fork = world.copy();
          final agents = {
            for (final p in fork.players) p.id: rolloutAgent(p.id, p.seat),
          };
          final action = actions[i]!;
          simulationEngine.applyAction(fork, _copyAction(action));
          rollouts++;
          final diff = await playOutRound(fork, agents);
          if (diff != null) row[i] = (team == 0 ? diff : -diff).toDouble();
          if (yieldBetweenRollouts) await Future<void>.delayed(Duration.zero);
        }
        values.add(row);
      }
      final pick = pickEndgameAction(
        values,
        chosenIndex,
        config.margin,
        minBetterWorlds: config.minBetterWorlds,
        weights: weights,
      );
      if (pick == chosenIndex) return chosen;
      switches++;
      return actions[pick]!;
    } finally {
      stopwatch.stop();
    }
  }

  /// Worlds in two strata, with and without a bomb in another player's
  /// hand, about half each, and their weights: the bomb probability
  /// (share of [EndgameSearch.bombProbes] re-deals with a bomb) spread
  /// over the bomb worlds, the rest over the others. Plain worlds with
  /// equal weights when the probes show no bomb or only bombs.
  static (List<GameEngineState>, List<double>?) _bombStrataWorlds(
    GameEngineState state,
    String playerId,
    Random random,
    List<List<double>>? holders,
    EndgameSearch config,
  ) {
    final bomb = <Map<String, List<Card>>>[];
    final plain = <Map<String, List<Card>>>[];
    for (var i = 0; i < config.bombProbes; i++) {
      final hands = dealUnseen(state, playerId, random, holders: holders);
      (hands.values.any(hasBombInHand) ? bomb : plain).add(hands);
    }
    GameEngineState worldOf(Map<String, List<Card>> hands) {
      final world = state.copy();
      hands.forEach((id, hand) => world.hands[id] = hand);
      return world;
    }

    if (bomb.isEmpty || plain.isEmpty) {
      final all = bomb.isEmpty ? plain : bomb;
      return ([for (final h in all.take(config.worlds)) worldOf(h)], null);
    }
    final p = bomb.length / config.bombProbes;
    final nBomb = min(bomb.length, max(1, config.worlds ~/ 2));
    final nPlain = min(plain.length, config.worlds - nBomb);
    return (
      [
        for (final h in bomb.take(nBomb)) worldOf(h),
        for (final h in plain.take(nPlain)) worldOf(h),
      ],
      [
        for (var i = 0; i < nBomb; i++) p / nBomb,
        for (var i = 0; i < nPlain; i++) (1 - p) / nPlain,
      ],
    );
  }

  /// Indices of the actions to roll out: all of them, or (above
  /// [maxActions]) the policy's move, pass, and the plays with the
  /// highest Q.
  static List<int> _candidates(
    SmartAiAgent agent,
    GameSnapshot snapshot,
    List<TichuTurn> turns, {
    required bool canPass,
    required int chosenIndex,
    required int maxActions,
  }) {
    final count = turns.length + (canPass ? 1 : 0);
    final all = [for (var i = 0; i < count; i++) i];
    if (count <= maxActions) return all;
    final keep = <int>{chosenIndex, if (canPass) turns.length};
    final strategy = agent.playSelectionStrategy;
    final order = [for (var i = 0; i < turns.length; i++) i];
    if (strategy is NnPlaySelectionStrategy) {
      final q = strategy.qValues(snapshot, turns);
      order.sort((a, b) => q[b].compareTo(q[a]));
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
  static int searchSeed(GameEngineState state, String actorId) {
    var h = 17;
    void mix(int x) => h = (h * 31 + x + 1) & 0x3FFFFFFF;
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
  static String slotKey(List<Card> cards) {
    final slots = [for (final c in cards) cardSlot(c)]..sort();
    return slots.join(',');
  }

  /// The Dragon gift to play instead of [chosen] (the rule's choice of
  /// [agent]): the solver's in a one-on-one endgame, else [chosen]. Who
  /// gets the trick matters there: the last player's tricks go to the
  /// first player out.
  Future<GameAction> refineDragonGift({
    required GameEngineState state,
    required PlayerAgent agent,
    required GiveDragonAction chosen,
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
      final current = state.players.firstWhere((p) => p.id == playerId);
      final solver = _solvers[current.seat % 2] ??= OneOnOneSolver(
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

  static bool _sameAction(GameAction a, GameAction b) {
    if (a is GiveDragonAction && b is GiveDragonAction) {
      return a.targetPlayerId == b.targetPlayerId;
    }
    if (a is PassAction && b is PassAction) return true;
    if (a is PlayTurnAction && b is PlayTurnAction) {
      return slotKey(a.cards) == slotKey(b.cards);
    }
    return false;
  }

  static GameAction _copyAction(GameAction action) => action is PlayTurnAction
      ? PlayTurnAction(
          playerId: action.playerId,
          cards: List<Card>.from(action.cards),
          inputWish: action.inputWish,
        )
      : action;
}
