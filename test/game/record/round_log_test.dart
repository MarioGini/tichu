import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/record/game_record_store.dart';
import 'package:tichu/game/record/round_log.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/screens/observe/observe_controller.dart';

void main() {
  test('card chars', () {
    expect(cardChar(Card(CardFace.two, CardColor.green)), 'A');
    expect(cardChar(Card(CardFace.two, CardColor.blue)), 'B');
    expect(cardChar(Card(CardFace.ace, CardColor.red)), 'z');
    expect(cardChar(Card(CardFace.mahJong, CardColor.special)), '0');
    expect(cardChar(Card(CardFace.dragon, CardColor.special)), '3');
    expect(cardChar(const Card.phoenix(10), inCombination: true), '~T');
    expect(cardChar(const Card.phoenix(7.5)), '2');
    expect(cardIndexLabel(cardIndex(Card(CardFace.ten, CardColor.red))), '10r');
  });

  test("full matches: every round replays with the engine's seats", () async {
    final sizes = <int>[];
    for (var match = 0; match < 10; match++) {
      final controller = ObserveController(
        store: InMemoryGameRecordStore(),
        phaseDelay: Duration.zero,
      );
      await controller.start();
      while (controller.step != ObserveStep.gameOver) {
        await controller.continueGame();
      }
      final record = controller.record!;
      final json =
          jsonDecode(jsonEncode(record.toJson())) as Map<String, Object?>;
      expect(json['format'], 3);
      final names = [for (var s = 0; s < 4; s++) record.playerAtSeat(s)!.name];
      final logs = (json['log']! as List).cast<String>();
      expect(logs, hasLength(record.roundsPlayed));
      final roundEnds = [
        for (final e in record.events)
          if (e.kind == 'roundEnd') e,
      ];
      for (var i = 0; i < logs.length; i++) {
        sizes.add(utf8.encode(jsonEncode(logs[i])).length);
        final steps = replayRoundLog(logs[i], names);
        expect(
          [for (final s in steps) s.seat],
          record.roundLogs[i].actionSeats,
          reason: 'round ${i + 1}: ${logs[i]}',
        );
        final left = (roundEnds[i].data['handsLeft']! as Map).map(
          (final k, final v) => MapEntry(k as String, (v as List).length),
        );
        for (var seat = 0; seat < 4; seat++) {
          final id = record.playerAtSeat(seat)!.id;
          expect(steps.last.hands[seat].length, left[id] ?? 0);
        }
      }
      controller.dispose();
    }
    sizes.sort();
    expect(sizes.last, lessThan(400), reason: 'round sizes: $sizes');
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('a card the seat does not hold is rejected', () {
    // Seat 0 is dealt fourteen 2s of green; the schupf passes a card it
    // does not hold.
    final log = '${'A' * 56}${'z' * 12}';
    expect(
      () => replayRoundLog(log, ['a', 'b', 'c', 'd']),
      throwsFormatException,
    );
  });

  test('an out-of-turn bomb is replayed with its seat', () {
    // Indices 0-55 dealt in order: seat 0 holds 0-13, seat 1 14-27 (with
    // the four 7s, 20-23), seat 2 28-41, seat 3 42-55 (the MahJong is 52,
    // so seat 3 leads).
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123';
    const deal = alphabet;
    // Everyone passes their last three cards; the 7s and MahJong stay.
    final schupf = StringBuffer();
    for (var seat = 0; seat < 4; seat++) {
      schupf.write(alphabet.substring(seat * 14 + 11, seat * 14 + 14));
    }
    final sevens = alphabet.substring(20, 24);
    // Seat 3 leads the MahJong, seat 1 bombs out of turn, then it is seat
    // 2's turn: it passes.
    final log = '$deal${schupf}0!1$sevens.';
    final steps = replayRoundLog(log, ['a', 'b', 'c', 'd']);
    expect([for (final s in steps) s.seat].skip(4), [3, 1, 2]);
    expect(steps[5].text, 'b plays 7g 7b 7k 7r');
  });
}
