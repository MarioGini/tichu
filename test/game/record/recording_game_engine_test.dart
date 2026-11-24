import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/endgame_search.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/record/recording_game_engine.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';

void main() {
  test('moves played on a fork of the game (endgame search) are not '
      'recorded', () async {
    final engine = RecordingGameEngine(GameEngineImpl());
    final players = [
      for (var seat = 0; seat < 4; seat++)
        GamePlayer(
          id: 'bot_$seat',
          name: 'Bot $seat',
          seat: seat,
          type: PlayerType.automated,
        ),
    ];
    final state = engine.createGame(gameId: 'g', players: players);
    engine.startGame(state);
    final record = engine.recordFor('g')!;
    final eventsBefore = record.events.length;
    final logBefore = record.roundLogs.single.encode();

    final agents = <String, PlayerAgent>{
      for (final p in players) p.id: SmartAiAgent(p.id),
    };
    final fork = state.copy();
    final diff = await playOutRound(engine, fork, agents);

    expect(diff, isNotNull);
    expect(fork.scoreTracker.state.roundComplete, isTrue);
    expect(record.events.length, eventsBefore);
    expect(record.roundLogs.single.encode(), logBefore);
    expect(record.actionCount, 0);

    // The real game is still recorded.
    await playOutRound(engine, state, agents);
    expect(record.actionCount, greaterThan(0));
  });
}
