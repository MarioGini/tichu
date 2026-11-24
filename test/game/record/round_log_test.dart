import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/record/game_record_store.dart';
import 'package:tichu/game/record/round_log.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/screens/observe/observe_controller.dart';

void main() {
  test('card codes', () {
    expect(cardCode(Card(CardFace.ten, CardColor.red)), 'Tr');
    expect(cardCode(Card(CardFace.ace, CardColor.green)), 'Ag');
    expect(cardCode(Card(CardFace.mahJong, CardColor.special)), 'MJ');
    expect(cardCode(Card(CardFace.phoenix, CardColor.special)), 'PH');
    expect(cardCode(const Card.phoenix(7)), 'P7');
    expect(cardCode(const Card.phoenix(7.5)), 'PH');
    expect(cardCodeLabel('Tr'), '10r');
    expect(cardCodeLabel('P7'), 'Phoenix');
  });

  test(
    'full matches: every round under 1000 bytes and replays exactly',
    () async {
      final sizes = <int>[];
      for (var match = 0; match < 3; match++) {
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
        final names = [
          for (var s = 0; s < 4; s++) record.playerAtSeat(s)!.name,
        ];
        final rounds = (json['log']! as List).cast<Map<String, Object?>>();
        expect(rounds, hasLength(record.roundsPlayed));

        final roundEnds = [
          for (final e in record.events)
            if (e.kind == 'roundEnd') e,
        ];
        for (var i = 0; i < rounds.length; i++) {
          final round = rounds[i];
          sizes.add(utf8.encode(jsonEncode(round)).length);
          final steps = describeRoundLog(round, names);
          // The replayed hands at the end match the cards left in the game.
          final left = (roundEnds[i].data['handsLeft']! as Map).map(
            (final k, final v) => MapEntry(k as String, (v as List).length),
          );
          for (var seat = 0; seat < 4; seat++) {
            final id = record.playerAtSeat(seat)!.id;
            expect(steps.last.hands[seat].length, left[id] ?? 0);
          }
          expect(round['r'], [
            roundEnds[i].data['teamOneRound'],
            roundEnds[i].data['teamTwoRound'],
          ]);
        }
        controller.dispose();
      }
      sizes.sort();
      expect(sizes.last, lessThan(1000), reason: 'round sizes: $sizes');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('a card the seat does not hold is rejected', () {
    final deal = List.filled(56, 'Ag').join();
    expect(
      () => describeRoundLog({'d': deal, 'm': '0Kr'}, ['a', 'b', 'c', 'd']),
      throwsFormatException,
    );
  });
}
