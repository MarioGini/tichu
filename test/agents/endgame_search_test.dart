import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/bot_config.dart';
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

SmartAiAgent _searchingBot(final String id) =>
    SmartAiAgent(id, endgameSearch: _search);

/// Plays heuristic games and collects on-turn endgame decisions the search
/// applies to (<= 5 cards, >= 2 actions, no finishing move).
(List<GameEngineState>, Future<void> Function()) _endgameStates(
  final GameEngine engine,
  final int n,
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
        PlayerAgent factory(final String id, final int _) {
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
            engine: engine,
            state: state,
            agent: agent,
            chosen: chosen,
          );
          expect(searcher.searches, before + 1);
          final b = await EndgameSearcher(rolloutAgent: factory).refine(
            engine: engine,
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
              options.turns.any(
                (final t) => EndgameSearcher.slotKey(t.cards) == key,
              ),
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

    test('skips decisions outside the endgame', () async {
      final searcher = EndgameSearcher(
        rolloutAgent: (final id, final _) {
          fail('no rollout expected');
        },
      );
      final state = engine.createGame(
        gameId: 'start',
        players: _players,
      );
      engine.startGame(state);
      final agent = _searchingBot('p1');
      const chosen = PassAction(playerId: 'p1');
      expect(
        await searcher.refine(
          engine: engine,
          state: state,
          agent: agent,
          chosen: chosen,
        ),
        same(chosen),
      );
      expect(searcher.searches, 0);
    });
  });
}

String _card(final Card c) => '${c.face.name}-${c.color.name}';

String _key(final GameAction a) => a is PlayTurnAction
    ? 'play ${EndgameSearcher.slotKey(a.cards)} ${a.inputWish}'
    : a.runtimeType.toString();
