import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/endgame_search.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/agent_decisions.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/record/recording_game_engine.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';

void main() {
  test('the endgame search does not leak its playouts into the game '
      'record', () async {
    final engine = RecordingGameEngine(GameEngineImpl(random: Random(3)));
    final players = [
      for (var seat = 0; seat < 4; seat++)
        GamePlayer(
          id: 'bot_$seat',
          name: 'Bot $seat',
          seat: seat,
          type: PlayerType.automated,
        ),
    ];
    final state = engine.createGame(
      gameId: 'g',
      players: players,
      targetScore: 100000,
    );
    engine.startGame(state);
    final record = engine.recordFor('g')!;
    final agents = {for (final p in players) p.id: SmartAiAgent(p.id)};
    final searcher = EndgameSearcher(
      rolloutAgent: (final id, final _) => SmartAiAgent(id),
    );

    // Play the real game; at every on-turn endgame decision, run the search
    // (as the app's AiTurnRunner does) and check the record is untouched.
    for (var steps = 0; searcher.rollouts < 50 && steps < 20000; steps++) {
      if (state.scoreTracker.state.roundComplete) {
        engine.startNewRound(state);
        continue;
      }
      final request = AgentDecisions.next(engine, state)!;
      final agent = agents[request.playerId]!;
      final snap = engine.buildSnapshot(state);
      var action = await AgentDecisions.resolve(request, agent, snap, state);
      if (action == null) continue;
      if (request is TurnRequest) {
        final events = record.events.length;
        final log = record.roundLogs.last.encode();
        action = await searcher.refine(
          state: state,
          agent: SmartAiAgent(
            request.playerId,
            endgameSearch: const EndgameSearch(worlds: 2),
          ),
          chosen: action,
        );
        expect(record.events.length, events);
        expect(record.roundLogs.last.encode(), log);
      }
      engine.applyAction(state, action);
    }
    expect(searcher.rollouts, greaterThanOrEqualTo(50));
  });
}
