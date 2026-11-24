import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/endgame_solver.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/agent_decisions.dart';
import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';

const _players = [
  GamePlayer(id: 'p1', name: 'P1', seat: 0, type: PlayerType.automated),
  GamePlayer(id: 'p2', name: 'P2', seat: 1, type: PlayerType.automated),
  GamePlayer(id: 'p3', name: 'P3', seat: 2, type: PlayerType.automated),
  GamePlayer(id: 'p4', name: 'P4', seat: 3, type: PlayerType.automated),
];

/// One-on-one positions (two players of different teams left, at most
/// [maxCards] cards together) from heuristic games.
Future<List<GameEngineState>> _oneOnOne(
  final GameEngine engine,
  final int n, {
  required final int maxCards,
}) async {
  final out = <GameEngineState>[];
  final state = engine.createGame(
    gameId: 'solver_test',
    players: _players,
    targetScore: 100000,
  );
  engine.startGame(state);
  final agents = {for (final p in _players) p.id: SmartAiAgent(p.id)};
  for (var steps = 0; out.length < n && steps < 40000; steps++) {
    if (state.scoreTracker.state.roundComplete) {
      engine.startNewRound(state);
      continue;
    }
    final request = AgentDecisions.next(engine, state);
    if (request == null) fail('no pending decision');
    if (request is TurnRequest &&
        OneOnOneSolver.applies(state, request.playerId, maxCards: maxCards)) {
      out.add(state.copy());
    }
    final action = await AgentDecisions.resolve(
      request,
      agents[request.playerId]!,
      engine.buildSnapshot(state),
      state,
    );
    if (action != null) engine.applyAction(state, action);
  }
  return out;
}

void main() {
  final engine = GameEngineImpl();
  SmartAiAgent bot(final String id, final int _) => SmartAiAgent(id);

  test('the solved move has the best exact value of all moves', () async {
    final states = await _oneOnOne(engine, 12, maxCards: 8);
    expect(states, isNotEmpty);
    for (final s in states) {
      final me = s.players[s.currentPlayerIndex].id;
      final solver = OneOnOneSolver(engine: engine, agentFor: bot);
      final solved = await solver.solve(s, me);
      expect(solved, isNotNull);
      final snap = engine.buildSnapshot(s);
      final options = SmartAiAgent(me).searchableActions(snap);
      if (options == null) continue; // forced or finishing move
      final actions = <GameAction>[
        for (final t in options.turns) SmartAiAgent(me).playActionFor(snap, t),
        if (options.canPass) PassAction(playerId: me),
      ];
      final values = await OneOnOneSolver(
        engine: engine,
        agentFor: bot,
      ).values(s, me, actions);
      final best = values.whereType<int>().fold<int>(
        -1 << 30,
        (a, b) => a > b ? a : b,
      );
      expect(solved!.value, best);
    }
  });

  test('memoised and plain minimax agree', () async {
    final states = await _oneOnOne(engine, 8, maxCards: 6);
    expect(states, isNotEmpty);
    for (final s in states) {
      final me = s.players[s.currentPlayerIndex].id;
      final a = await OneOnOneSolver(
        engine: engine,
        agentFor: bot,
      ).solve(s, me);
      final b = await OneOnOneSolver(
        engine: engine,
        agentFor: bot,
        memoize: false,
        nodeBudget: 1 << 30,
      ).solve(s, me);
      expect(a?.value, b?.value);
    }
  });

  test('applies only to one-on-one positions of the player to move', () async {
    final state = engine.createGame(gameId: 'solver_start', players: _players);
    engine.startGame(state);
    expect(OneOnOneSolver.applies(state, 'p1'), isFalse);
  });
}
