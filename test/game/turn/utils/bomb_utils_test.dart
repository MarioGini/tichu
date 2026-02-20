import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/bomb_utils.dart';

void main() {
  group('getBombs', () {
    test('twoQuartetBombTest', () {
      final cards = <Card>[
        Card(CardFace.eight, CardColor.black),
        Card(CardFace.eight, CardColor.green),
        Card(CardFace.eight, CardColor.red),
        Card(CardFace.eight, CardColor.blue),
        Card(CardFace.jack, CardColor.black),
        Card(CardFace.jack, CardColor.green),
        Card(CardFace.jack, CardColor.red),
        Card(CardFace.jack, CardColor.blue),
      ];

      final turns = getBombs(cards);
      expect(turns.length, 2);
      expect(turns.every((final turn) => turn.type == TurnType.bomb), true);
      expect(
        turns.any((final turn) => turn.value == Card.getValue(CardFace.eight)),
        true,
      );
      expect(
        turns.any((final turn) => turn.value == Card.getValue(CardFace.jack)),
        true,
      );
    });
    test('noBombTest', () {
      final cards = <Card>[
        Card(CardFace.eight, CardColor.black),
        Card(CardFace.eight, CardColor.green),
        Card(CardFace.eight, CardColor.red),
        Card(CardFace.jack, CardColor.black),
        Card(CardFace.jack, CardColor.green),
      ];

      final turns = getBombs(cards);
      expect(turns.length, 0);
    });

    test('nonUniformStraightIsNotBomb', () {
      final cards = <Card>[
        Card(CardFace.eight, CardColor.black),
        Card(CardFace.nine, CardColor.red),
        Card(CardFace.ten, CardColor.black),
        Card(CardFace.jack, CardColor.black),
        Card(CardFace.queen, CardColor.black),
      ];

      final turns = getBombs(cards);
      expect(turns, isEmpty);
    });

    test('phoenixDoesNotCreateStraightBomb', () {
      final cards = <Card>[
        Card(CardFace.eight, CardColor.black),
        Card(CardFace.nine, CardColor.black),
        Card(CardFace.ten, CardColor.black),
        Card(CardFace.jack, CardColor.black),
        Card(CardFace.phoenix, CardColor.special),
      ];

      final turns = getBombs(cards);
      expect(turns, isEmpty);
    });

    test('twoStraightBombsSameSuit', () {
      final cards = <Card>[
        Card(CardFace.two, CardColor.black),
        Card(CardFace.three, CardColor.black),
        Card(CardFace.four, CardColor.black),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.six, CardColor.black),
        Card(CardFace.nine, CardColor.black),
        Card(CardFace.ten, CardColor.black),
        Card(CardFace.jack, CardColor.black),
        Card(CardFace.queen, CardColor.black),
        Card(CardFace.king, CardColor.black),
      ];

      final turns = getBombs(cards);
      expect(turns.length, 2);
      expect(
        turns.any((final turn) => turn.value == 20 + Card.getValue(CardFace.six)),
        true,
      );
      expect(
        turns.any((final turn) => turn.value == 20 + Card.getValue(CardFace.king)),
        true,
      );
    });
  });
  group('isBomb', () {
    test('quartetBombTest', () {
      final cards = <Card>[
        Card(CardFace.eight, CardColor.black),
        Card(CardFace.eight, CardColor.green),
        Card(CardFace.eight, CardColor.red),
        Card(CardFace.eight, CardColor.blue),
      ];
      expect(getBombs(cards).length, 1);
    });
    test('straightBombTest', () {
      final cards = <Card>[
        Card(CardFace.eight, CardColor.black),
        Card(CardFace.nine, CardColor.black),
        Card(CardFace.ten, CardColor.black),
        Card(CardFace.jack, CardColor.black),
        Card(CardFace.queen, CardColor.black),
        Card(CardFace.king, CardColor.black),
      ];
      expect(getBombs(cards).length, 1);
    });
  });
  group('hasBombInHand', () {
    test('returnsTrueForQuartetBomb', () {
      final cards = <Card>[
        Card(CardFace.eight, CardColor.black),
        Card(CardFace.eight, CardColor.green),
        Card(CardFace.eight, CardColor.red),
        Card(CardFace.eight, CardColor.blue),
        Card(CardFace.jack, CardColor.black),
      ];

      expect(hasBombInHand(cards), true);
    });

    test('returnsTrueForStraightBomb', () {
      final cards = <Card>[
        Card(CardFace.six, CardColor.red),
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.eight, CardColor.red),
        Card(CardFace.nine, CardColor.red),
        Card(CardFace.ten, CardColor.red),
      ];

      expect(hasBombInHand(cards), true);
    });

    test('returnsFalseWhenNoBombExists', () {
      final cards = <Card>[
        Card(CardFace.eight, CardColor.black),
        Card(CardFace.eight, CardColor.green),
        Card(CardFace.nine, CardColor.red),
        Card(CardFace.jack, CardColor.black),
        Card(CardFace.queen, CardColor.green),
      ];

      expect(hasBombInHand(cards), false);
    });
  });
}
