import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/endgame_search.dart';
import 'package:tichu/agents/halving_search.dart';
import 'package:tichu/agents/nn/mlp.dart';
import 'package:tichu/agents/nn/value_model.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/agent_decisions.dart';
import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/simulation.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';

/// A world evaluator with true action values [truth] plus world noise
/// shared by all actions (the luck of the deal) and a little own noise.
WorldEvaluator _noisy(List<double> truth, {int seed = 1, double luck = 50}) {
  final worlds = <int, double>{};
  return (ws, actions) async => [
    for (final w in ws)
      [
        for (final a in actions)
          truth[a] +
              (worlds[w] ??=
                  (Random(seed * 1000 + w).nextDouble() - 0.5) * luck) +
              (Random(w * 97 + a).nextDouble() - 0.5) * 4,
      ],
  ];
}

const _players = [
  GamePlayer(id: 'p1', name: 'P1', seat: 0, type: PlayerType.automated),
  GamePlayer(id: 'p2', name: 'P2', seat: 1, type: PlayerType.automated),
  GamePlayer(id: 'p3', name: 'P3', seat: 2, type: PlayerType.automated),
  GamePlayer(id: 'p4', name: 'P4', seat: 3, type: PlayerType.automated),
];

/// On-turn decisions with at least [minActions] actions from heuristic
/// games.
Future<List<GameEngineState>> _states(
  GameEngine engine,
  int n, {
  int minActions = 3,
}) async {
  final out = <GameEngineState>[];
  final state = engine.createGame(
    gameId: 'halving_test',
    players: _players,
    targetScore: 100000,
  );
  engine.startGame(state);
  final agents = {for (final p in _players) p.id: SmartAiAgent(p.id)};
  for (var steps = 0; out.length < n && steps < 20000; steps++) {
    if (state.scoreTracker.state.roundComplete) {
      engine.startNewRound(state);
      continue;
    }
    final request = AgentDecisions.next(engine, state)!;
    final snap = engine.buildSnapshot(state);
    if (request is TurnRequest && steps % 3 == 0) {
      final options = agents[request.playerId]!.searchableActions(snap);
      if (options != null &&
          options.turns.length + (options.canPass ? 1 : 0) >= minActions) {
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
  return out;
}

String _key(GameAction a) => a is PlayTurnAction
    ? EndgameSearcher.slotKey(a.cards)
    : a.runtimeType.toString();

void main() {
  group('sequentialHalving', () {
    test('finds the best action and keeps the budget', () async {
      final truth = <double>[0, 3, -10, 25, 1, -4, 8, 2];
      final r = await sequentialHalving(
        count: truth.length,
        incumbent: 0,
        budget: 120,
        evaluate: _noisy(truth),
        margin: 5,
      );
      expect(r.pick, 3);
      expect(r.advantage, closeTo(25, 3));
      expect(r.evaluations, lessThanOrEqualTo(120));
      // The final pair got most of the worlds.
      expect(r.samples[3], greaterThan(r.samples[2]));
      expect(r.samples[0], r.samples[3]);
    });

    test('keeps the incumbent without a clear gain', () async {
      final truth = <double>[10, 12, 4, -3];
      final r = await sequentialHalving(
        count: truth.length,
        incumbent: 0,
        budget: 64,
        evaluate: _noisy(truth),
        margin: 5,
      );
      expect(r.pick, 0);
    });

    test('paired worlds cancel the luck of the deal', () async {
      // World luck +-500 would swamp a 6-point gain without pairing.
      final r = await sequentialHalving(
        count: 2,
        incumbent: 1,
        budget: 40,
        evaluate: _noisy([6, 0], luck: 1000),
        margin: 3,
        minZ: 2,
      );
      expect(r.pick, 0);
      expect(r.standardError, lessThan(2));
    });

    test('the prior breaks near-ties toward the net', () async {
      // Two challengers with equal true value; the prior keeps 2.
      final truth = <double>[0, 20, 20, -5];
      final r = await sequentialHalving(
        count: truth.length,
        incumbent: 0,
        budget: 24,
        evaluate: _noisy(truth, luck: 0),
        prior: [0, 0, 10, 0],
        priorWeight: 1,
      );
      expect(r.pick, 2);
      expect(r.means[1], isNotNull);
    });

    test('an action that gets stuck is dropped', () async {
      final r = await sequentialHalving(
        count: 3,
        incumbent: 0,
        budget: 30,
        evaluate: (ws, actions) async => [
          for (final _ in ws)
            [
              for (final a in actions)
                if (a == 2) null else a * 20.0,
            ],
        ],
        margin: 5,
      );
      expect(r.pick, 1);
      expect(r.samples[2], 0);
    });
  });

  group('EndgameSearcher with halving', () {
    late List<GameEngineState> states;
    late GameEngine engine;

    setUpAll(() async {
      engine = GameEngineImpl(random: Random(11));
      states = await _states(engine, 6);
      expect(states.length, 6);
    });

    Future<void> checkLegalAndDeterministic(
      EndgameSearch config, {
      ValueModel? value,
    }) async {
      final searcher = EndgameSearcher(
        rolloutAgent: (id, _) => SmartAiAgent(id),
        value: value,
      );
      for (final state in states) {
        final id = state.players[state.currentPlayerIndex].id;
        final agent = SmartAiAgent(id, endgameSearch: config);
        final snapshot = engine.buildSnapshot(state);
        final chosen = await agent.selectTurn(snapshot);
        final a = await searcher.refine(
          state: state,
          agent: agent,
          chosen: chosen,
        );
        final b =
            await EndgameSearcher(
              rolloutAgent: (id, _) => SmartAiAgent(id),
              value: value,
            ).refine(
              state: state.copy(),
              agent: SmartAiAgent(id, endgameSearch: config),
              chosen: chosen,
            );
        expect(_key(a), _key(b), reason: 'deterministic');
        simulationEngine.applyAction(state.copy(), a);
      }
      expect(searcher.searches, states.length);
      expect(searcher.rollouts, lessThanOrEqualTo(states.length * 24));
    }

    test('full rollouts: legal, deterministic, within budget', () async {
      await checkLegalAndDeterministic(
        const EndgameSearch(maxCards: 14, maxActions: 10, halvingBudget: 24),
      );
    });

    test('truncated rollouts with a value net and match utility', () async {
      await checkLegalAndDeterministic(
        const EndgameSearch(
          maxCards: 14,
          maxActions: 10,
          halvingBudget: 24,
          leafAfter: 4,
          matchUtility: true,
          beliefWorlds: true,
        ),
        value: ValueModel(
          Mlp(layerSizes: [valueFeatureCount, 8, valueOutputCount], seed: 5),
        ),
      );
    });
  });

  test('playOutRoundPoints stops at the leaf', () async {
    final engine = GameEngineImpl(random: Random(3));
    final state = (await _states(engine, 1, minActions: 1)).single;
    var calls = 0;
    final points = await playOutRoundPoints(
      state.copy(),
      {for (final p in state.players) p.id: SmartAiAgent(p.id)},
      leafAfter: 2,
      leaf: (s, id) {
        calls++;
        expect(s.hands[id], isNotEmpty);
        return (7, 3);
      },
    );
    final full = await playOutRoundPoints(state.copy(), {
      for (final p in state.players) p.id: SmartAiAgent(p.id),
    });
    expect(calls, lessThanOrEqualTo(1));
    if (calls == 1) expect(points, (7.0, 3.0));
    expect(full, isNotNull);
  });
}
