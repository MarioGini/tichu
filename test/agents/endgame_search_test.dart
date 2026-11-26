import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/bot_config.dart';
import 'package:tichu/agents/card_knowledge.dart';
import 'package:tichu/agents/endgame_search.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/agent_decisions.dart';
import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';
import 'package:tichu/game/turn/tichu_data.dart';

const _search = EndgameSearch(worlds: 4, margin: 10);

const _players = [
  GamePlayer(id: 'p1', name: 'P1', seat: 0, type: PlayerType.automated),
  GamePlayer(id: 'p2', name: 'P2', seat: 1, type: PlayerType.automated),
  GamePlayer(id: 'p3', name: 'P3', seat: 2, type: PlayerType.automated),
  GamePlayer(id: 'p4', name: 'P4', seat: 3, type: PlayerType.automated),
];

/// Rollout bots of [config]; top level, so the closure captures only the
/// config (it is sent to isolates).
PlayerAgent Function(String, int) _rolloutFactory(BotConfig config) =>
    (id, _) => config.build(id);

SmartAiAgent _searchingBot(String id) =>
    SmartAiAgent(id, endgameSearch: _search);

/// Plays heuristic games and collects on-turn endgame decisions the search
/// applies to (<= 5 cards, >= 2 actions, no finishing move).
(List<GameEngineState>, Future<void> Function()) _endgameStates(
  GameEngine engine,
  int n,
) {
  final out = <GameEngineState>[];
  final state = engine.createGame(
    gameId: 'endgame_test',
    players: _players,
    targetScore: 100000,
  );
  engine.startGame(state);
  final agents = {for (final p in _players) p.id: SmartAiAgent(p.id)};
  var steps = 0;
  Future<void> run() async {
    while (out.length < n && steps++ < 20000) {
      if (state.scoreTracker.state.roundComplete) {
        engine.startNewRound(state);
        continue;
      }
      final request = AgentDecisions.next(engine, state);
      if (request == null) fail('no pending decision');
      final snap = engine.buildSnapshot(state);
      if (request is TurnRequest) {
        final hand = state.hands[request.playerId]!;
        final options = agents[request.playerId]!.searchableActions(snap);
        if (hand.length <= 5 &&
            options != null &&
            options.turns.length + (options.canPass ? 1 : 0) >= 2 &&
            steps.isEven) {
          out.add(state.copy());
        }
      }
      final action = await AgentDecisions.resolve(
        request,
        agents[request.playerId]!,
        snap,
        state,
      );
      if (action != null) engine.applyAction(state, action);
    }
  }

  return (out, run);
}

void main() {
  group('pickEndgameAction', () {
    test('keeps the choice without a unanimous improvement', () {
      // Action 1 is better on average by 50 but worse in one world.
      final values = [
        [0.0, 100.0],
        [0.0, 100.0],
        [0.0, -1.0],
        [0.0, 1.0],
      ];
      expect(pickEndgameAction(values, 0, 10), 0);
    });

    test('needs more than the margin on average', () {
      final values = [
        [0.0, 10.0, 0.0],
        [0.0, 10.0, 40.0],
      ];
      // Action 1: +10 (not > 10); action 2: +20 and never worse.
      expect(pickEndgameAction(values, 0, 10), 2);
      expect(pickEndgameAction(values, 0, 20), 0);
      expect(pickEndgameAction([values.first], 0, 9), 1);
    });

    test('needs enough worlds that are strictly better', () {
      // Game 13cb: the policy's Dragon and the pass tie in 7 of 8 worlds;
      // one world favours the pass by 90 (mean +11.25 > 10).
      final values = [
        for (var w = 0; w < 8; w++) [-100.0, -100.0],
      ];
      values[5] = [-100.0, -10.0];
      expect(pickEndgameAction(values, 0, 10), 1);
      expect(pickEndgameAction(values, 0, 10, minBetterWorlds: 2), 0);
      values[2] = [-100.0, -90.0];
      expect(pickEndgameAction(values, 0, 10, minBetterWorlds: 2), 1);
      // Capped at the number of worlds.
      expect(
        pickEndgameAction(
          [
            [0.0, 50.0],
          ],
          0,
          10,
          minBetterWorlds: 2,
        ),
        1,
      );
    });

    test('weights the mean advantage by world', () {
      final values = [
        [0.0, 90.0],
        [0.0, 90.0],
        [0.0, 0.0],
        [0.0, 0.0],
      ];
      // Equal weights: +45. Bomb worlds (first two) at 17 %: +15.3.
      expect(pickEndgameAction(values, 0, 10, minBetterWorlds: 2), 1);
      const w = [0.085, 0.085, 0.415, 0.415];
      expect(
        pickEndgameAction(values, 0, 10, minBetterWorlds: 2, weights: w),
        1,
      );
      expect(
        pickEndgameAction(values, 0, 20, minBetterWorlds: 2, weights: w),
        0,
      );
    });

    test('picks the highest mean advantage among eligible actions', () {
      final values = [
        [5.0, 30.0, 25.0, 100.0],
        [5.0, 30.0, 85.0, 0.0],
      ];
      // 1: +25, 2: +50, 3: worse in world 2.
      expect(pickEndgameAction(values, 0, 10), 2);
    });

    test('missing rollouts make an action ineligible', () {
      expect(
        pickEndgameAction(
          [
            [0.0, 50.0, null],
            [0.0, null, 80.0],
          ],
          0,
          0,
        ),
        0,
      );
      expect(
        pickEndgameAction(
          [
            [null, 50.0],
          ],
          0,
          0,
        ),
        0,
      );
    });
  });

  test('BotConfig gives the search only to bots with a play net', () {
    final agent =
        BotConfig.heuristic.withEndgameSearch(_search).build('p1')
            as SmartAiAgent;
    expect(agent.endgameSearch, isNull);
  });

  group('EndgameSearcher', () {
    late List<GameEngineState> states;
    late GameEngine engine;

    setUpAll(() async {
      engine = GameEngineImpl(random: Random(7));
      final (out, run) = _endgameStates(engine, 12);
      await run();
      states = out;
      expect(states.length, 12);
    });

    test(
      'returns a legal action, deterministically, without recursion',
      () async {
        var rolloutAgents = 0;
        PlayerAgent factory(String id, int _) {
          rolloutAgents++;
          // Rollout bots carry a search config too: only the searcher runs a
          // search, and it never calls itself from a rollout.
          return _searchingBot(id);
        }

        final searcher = EndgameSearcher(rolloutAgent: factory);
        for (final state in states) {
          final id = state.players[state.currentPlayerIndex].id;
          final agent = _searchingBot(id);
          final snapshot = engine.buildSnapshot(state);
          final chosen = await agent.selectTurn(snapshot);
          final before = searcher.searches;
          final a = await searcher.refine(
            state: state,
            agent: agent,
            chosen: chosen,
          );
          expect(searcher.searches, before + 1);
          final b = await EndgameSearcher(rolloutAgent: factory).refine(
            state: state.copy(),
            agent: _searchingBot(id),
            chosen: chosen,
          );
          expect(_key(a), _key(b), reason: 'deterministic');

          final options = agent.searchableActions(snapshot)!;
          if (a is PassAction) {
            expect(options.canPass, isTrue);
          } else {
            final key = EndgameSearcher.slotKey((a as PlayTurnAction).cards);
            expect(
              options.turns.any((t) => EndgameSearcher.slotKey(t.cards) == key),
              isTrue,
            );
          }
          // The engine accepts it.
          engine.applyAction(state.copy(), a);
        }
        expect(rolloutAgents, greaterThan(0));
        // Each searched decision rolls out at most maxActions actions in
        // every world, four fresh bots per rollout.
        expect(
          rolloutAgents,
          lessThanOrEqualTo(2 * states.length * _search.worlds * 7 * 4),
        );
      },
    );

    test('parallel worlds on isolates give the same moves', () async {
      final config = BotConfig(
        play: LoadedNet.fromBytes(
          File('assets/bots/tichu_q_v10.safetensors').readAsBytesSync(),
        ),
        simdInference: true,
      );
      final searching = config.withEndgameSearch(_search);
      final serial = EndgameSearcher(rolloutAgent: _rolloutFactory(config));
      final parallel = EndgameSearcher(
        rolloutAgent: _rolloutFactory(config),
        runWorlds: Isolate.run,
        parallelism: 3,
      );
      for (final state in states.take(4)) {
        final id = state.players[state.currentPlayerIndex].id;
        final agent = searching.build(id);
        final chosen = await agent.selectTurn(engine.buildSnapshot(state));
        final a = await serial.refine(
          state: state.copy(),
          agent: agent,
          chosen: chosen,
        );
        final b = await parallel.refine(
          state: state.copy(),
          agent: agent,
          chosen: chosen,
        );
        expect(_key(b), _key(a));
      }
      expect(parallel.rollouts, serial.rollouts);
    });

    test('the seed depends only on what the decider knows', () {
      final state = states.first;
      final id = state.players[state.currentPlayerIndex].id;
      final seed = EndgameSearcher.searchSeed(state, id);
      expect(EndgameSearcher.searchSeed(state.copy(), id), seed);
      // Swapping hidden cards between two other players keeps the seed.
      final swapped = state.copy();
      final others = [
        for (final p in swapped.players)
          if (p.id != id && swapped.hands[p.id]!.isNotEmpty) p.id,
      ];
      if (others.length >= 2) {
        final a = swapped.hands[others[0]]!;
        final b = swapped.hands[others[1]]!;
        final t = a.first;
        a[0] = b.first;
        b[0] = t;
        expect(EndgameSearcher.searchSeed(swapped, id), seed);
      }
    });

    test('re-deals keep the decider hand and every hand size', () {
      for (final state in states) {
        final id = state.players[state.currentPlayerIndex].id;
        final world = redealWorld(state, id, Random(1));
        expect(world.hands[id], state.hands[id]);
        final unseen = <String>[];
        final redealt = <String>[];
        for (final p in state.players) {
          expect(world.hands[p.id]!.length, state.hands[p.id]!.length);
          if (p.id == id) continue;
          unseen.addAll(state.hands[p.id]!.map(_card));
          redealt.addAll(world.hands[p.id]!.map(_card));
        }
        expect(redealt..sort(), unseen..sort());
      }
    });

    test('belief re-deals keep the hand sizes and follow the holders', () {
      var withBelief = 0;
      var uniform = 0;
      var trials = 0;
      for (final state in states) {
        final id = state.players[state.currentPlayerIndex].id;
        final me = state.players.firstWhere((p) => p.id == id);
        final partner = state.players
            .firstWhere((p) => p.seat == (me.seat + 2) % 4)
            .id;
        if (state.hands[partner]!.isEmpty) continue;
        // One unseen card the partner does not hold; the belief says he does.
        final others = [
          for (final p in state.players)
            if (p.id != id && p.id != partner) ...state.hands[p.id]!,
        ];
        if (others.isEmpty) continue;
        final card = others.first;
        final holders = List.generate(56, (_) => [1 / 3, 1 / 3, 1 / 3]);
        holders[cardSlot(card)] = [0.01, 0.98, 0.01];
        for (var k = 0; k < 20; k++) {
          final world = redealWorld(state, id, Random(k), holders: holders);
          expect(world.hands[id], state.hands[id]);
          for (final p in state.players) {
            expect(world.hands[p.id]!.length, state.hands[p.id]!.length);
          }
          if (world.hands[partner]!.any((c) => _card(c) == _card(card))) {
            withBelief++;
          }
          final flat = redealWorld(state, id, Random(k));
          if (flat.hands[partner]!.any((c) => _card(c) == _card(card))) {
            uniform++;
          }
          trials++;
        }
      }
      expect(trials, greaterThan(0));
      expect(withBelief, greaterThan(uniform + trials ~/ 5));
    });

    test('skips decisions outside the endgame', () async {
      final searcher = EndgameSearcher(
        rolloutAgent: (id, _) {
          fail('no rollout expected');
        },
      );
      final state = engine.createGame(gameId: 'start', players: _players);
      engine.startGame(state);
      final agent = _searchingBot('p1');
      const chosen = PassAction(playerId: 'p1');
      expect(
        await searcher.refine(state: state, agent: agent, chosen: chosen),
        same(chosen),
      );
      expect(searcher.searches, 0);
    });
  });
}

String _card(Card c) => '${c.face.name}-${c.color.name}';

String _key(GameAction a) => a is PlayTurnAction
    ? 'play ${EndgameSearcher.slotKey(a.cards)} ${a.inputWish}'
    : a.runtimeType.toString();
