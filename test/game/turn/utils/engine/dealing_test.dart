import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/card_identifiers.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/engine/dealing.dart';

import '../../../../utils/test_game_fixtures.dart';

void main() {
  group('dealInitialHands', () {
    test('deals 8 hand cards and 6 reserved cards for each player', () {
      final (hands, reserved) = dealInitialHands(testPlayers, Random(42));

      for (final player in testPlayers) {
        expect(hands[player.id], hasLength(8));
        expect(reserved[player.id], hasLength(6));
      }
    });

    test('deals exactly all unique cards in the deck', () {
      final (hands, reserved) = dealInitialHands(testPlayers, Random(7));

      final dealt = <Card>{};
      for (final player in testPlayers) {
        dealt.addAll(hands[player.id]!);
        dealt.addAll(reserved[player.id]!);
      }

      expect(dealt.length, cardIdentifiers.length);
      expect(cardIdentifiers.values.toSet().difference(dealt), isEmpty);
    });
  });
}
