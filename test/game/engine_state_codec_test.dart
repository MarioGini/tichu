import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/agent_decisions.dart';
import 'package:tichu/game/engine.dart';
import 'package:tichu/game/engine_state_codec.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/simulation.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';

const _players = [
  GamePlayer(id: 'p1', name: 'P1', seat: 0, type: PlayerType.automated),
  GamePlayer(id: 'p2', name: 'P2', seat: 1, type: PlayerType.automated),
  GamePlayer(id: 'p3', name: 'P3', seat: 2, type: PlayerType.automated),
  GamePlayer(id: 'p4', name: 'P4', seat: 3, type: PlayerType.automated),
];

GameEngineState _roundTrip(GameEngineState s) => decodeEngineState(
  jsonDecode(jsonEncode(encodeEngineState(s))) as Map<String, Object?>,
);

void main() {
  test(
    'every state of whole rounds survives JSON and plays out the same',
    () async {
      final engine = GameEngineImpl(random: Random(11));
      final state = engine.createGame(gameId: 'codec', players: _players);
      engine.startGame(state);
      final agents = {for (final p in _players) p.id: SmartAiAgent(p.id)};
      var checked = 0;
      var playedOut = 0;
      for (var steps = 0; steps < 3000; steps++) {
        if (state.scoreTracker.state.gameComplete) break;
        if (state.scoreTracker.state.roundComplete) {
          engine.startNewRound(state);
          continue;
        }
        final json = jsonEncode(encodeEngineState(state));
        final copy = _roundTrip(state);
        expect(jsonEncode(encodeEngineState(copy)), json);
        checked++;
        if (steps % 25 == 0) {
          // Fresh heuristic bots are deterministic: same state, same result.
          Map<String, SmartAiAgent> bots() => {
            for (final p in _players) p.id: SmartAiAgent(p.id),
          };
          final a = await playOutRound(state.copy(), bots());
          final b = await playOutRound(copy, bots());
          expect(b, a);
          playedOut++;
        }
        final request = AgentDecisions.next(engine, state)!;
        final action = await AgentDecisions.resolve(
          request,
          agents[request.playerId]!,
          engine.buildSnapshot(state),
          state,
        );
        if (action != null) engine.applyAction(state, action);
      }
      expect(checked, greaterThan(500));
      expect(playedOut, greaterThan(20));
    },
  );

  test('search actions survive JSON', () {
    final card = _roundTrip(
      GameEngineImpl(random: Random(3))
          .createGame(gameId: 'a', players: _players),
    ).hands['p1']!;
    for (final action in <GameAction>[
      const PassAction(playerId: 'p2'),
      PlayTurnAction(playerId: 'p1', cards: card.take(2).toList()),
    ]) {
      final back = decodeSearchAction(
        jsonDecode(jsonEncode(encodeSearchAction(action))),
      );
      expect(
        jsonEncode(encodeSearchAction(back)),
        jsonEncode(encodeSearchAction(action)),
      );
    }
  });
}
