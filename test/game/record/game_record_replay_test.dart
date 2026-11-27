import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/record/game_record_replay.dart';
import 'package:tichu/game/record/game_record_store.dart';
import 'package:tichu/game/record/round_log.dart';
import 'package:tichu/game/simulation.dart';
import 'package:tichu/screens/observe/observe_controller.dart';

void main() {
  test('recorded matches replay to the same points and hands', () async {
    for (var match = 0; match < 4; match++) {
      final controller = ObserveController(
        store: InMemoryGameRecordStore(),
        phaseDelay: Duration.zero,
      );
      await controller.start();
      while (controller.step != ObserveStep.gameOver) {
        await controller.continueGame();
      }
      final record = controller.record!;
      final logs = [for (final r in record.roundLogs) r.encode()];
      final players = record.players;
      final names = [for (var s = 0; s < 4; s++) record.playerAtSeat(s)!.name];

      // Every round, replayed on its own, ends with the recorded points.
      for (var i = 0; i < logs.length; i++) {
        final state = replayGameRecord(
          engine: simulationEngine,
          players: players,
          rounds: logs.sublist(0, i + 1),
          targetScore: 100000,
        );
        final score = state.scoreTracker.state;
        expect(score.roundComplete, isTrue, reason: 'round ${i + 1}');
        expect(score.teamOneRound, record.roundLogs[i].teamOnePoints);
        expect(score.teamTwoRound, record.roundLogs[i].teamTwoPoints);
      }

      // Stopping before a play: the hands are those after the previous
      // action, and the player of that play is to act.
      final steps = replayRoundLog(logs.last, names);
      final first = logs.length - 1;
      final offset = [
        for (final l in logs.take(first)) replayRoundLog(l, names).length,
      ].fold(0, (a, b) => a + b);
      for (var k = 1; k < steps.length; k++) {
        if (steps[k].kind != RoundLogKind.play) continue;
        final state = replayGameRecord(
          engine: simulationEngine,
          players: players,
          rounds: logs,
          targetScore: 100000,
          before: offset + k + 1,
        );
        for (var seat = 0; seat < 4; seat++) {
          final id = record.playerAtSeat(seat)!.id;
          expect(
            [for (final c in state.hands[id]!) cardIndex(c)]..sort(),
            [...steps[k - 1].hands[seat]]..sort(),
          );
        }
      }
      controller.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
