import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/card_identifiers.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/bomb_utils.dart';
import 'package:tichu/game/turn/utils/card_utils.dart';

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
        turns.any(
          (final turn) => turn.value == 20 + Card.getValue(CardFace.six),
        ),
        true,
      );
      expect(
        turns.any(
          (final turn) => turn.value == 20 + Card.getValue(CardFace.king),
        ),
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

  // getBombs / hasBombInHand answer "no bomb" from bit masks first; they
  // must agree with the full search on every input, including impossible
  // hands (duplicates, special faces in a suit colour).
  test('fast bomb check agrees with the full search', () {
    final deck = cardIdentifiers.values.toList();
    final weird = [
      ...deck,
      Card(CardFace.mahJong, CardColor.red),
      Card(CardFace.phoenix, CardColor.black),
      Card(CardFace.dog, CardColor.green),
      Card(CardFace.none, CardColor.blue),
      const Card.phoenix(7.5),
    ];
    final rng = Random(3);
    const suits = [
      CardColor.black,
      CardColor.green,
      CardColor.red,
      CardColor.blue,
    ];
    var bombs = 0;
    for (var i = 0; i < 20000; i++) {
      final hand = <Card>[];
      switch (i % 4) {
        case 0: // a real hand
          hand.addAll((deck.toList()..shuffle(rng)).take(rng.nextInt(15)));
        case 1: // a run in one suit plus filler
          final suit = suits[rng.nextInt(4)];
          final low = 2 + rng.nextInt(9);
          final len = 3 + rng.nextInt(6);
          for (var r = low; r < low + len && r <= 14; r++) {
            hand.add(Card(CardFace.values[r], suit));
          }
          for (final c in (deck.toList()..shuffle(rng)).take(rng.nextInt(8))) {
            if (!hand.contains(c)) hand.add(c);
          }
          hand.shuffle(rng);
        case 2: // three or four of a face plus filler
          final face = CardFace.values[2 + rng.nextInt(13)];
          for (final s in (suits.toList()..shuffle(rng)).take(
            3 + rng.nextInt(2),
          )) {
            hand.add(Card(face, s));
          }
          for (final c in (deck.toList()..shuffle(rng)).take(rng.nextInt(10))) {
            if (!hand.contains(c)) hand.add(c);
          }
          hand.shuffle(rng);
        default: // impossible hands: drawn with replacement
          for (var k = rng.nextInt(17); k > 0; k--) {
            hand.add(weird[rng.nextInt(weird.length)]);
          }
      }
      final expected = _referenceBombs(hand);
      if (expected.isNotEmpty) bombs++;
      expect(hasBombInHand(hand), expected.isNotEmpty, reason: '$i');
      final actual = getBombs(hand);
      expect(actual.length, expected.length, reason: '$i');
      for (var k = 0; k < actual.length; k++) {
        expect(actual[k].type, expected[k].type);
        expect(actual[k].value, expected[k].value);
        expect(actual[k].cards, expected[k].cards);
      }
    }
    expect(bombs, greaterThan(2000));
  });
}

/// getBombs as it was before the bit-mask shortcut.
List<TichuTurn> _referenceBombs(final List<Card> cards) {
  final bombTurns = <TichuTurn>[];
  final occurrenceCount = getOccurrenceCount(cards);
  final bombFaces = occurrenceCount.keys
      .where((final element) => occurrenceCount[element] == 4)
      .toList();
  for (final bombFace in bombFaces) {
    bombTurns.add(
      TichuTurn(
        TurnType.bomb,
        cards.where((final card) => card.face == bombFace).toList(),
      ),
    );
  }
  final suitedCards = cards
      .where((final card) => card.color != CardColor.special)
      .toList();
  for (final color in CardColor.values.where((c) => c != CardColor.special)) {
    final colorCards =
        suitedCards.where((final card) => card.color == color).toList()
          ..sort(compareCards);
    if (colorCards.length < 5) continue;
    var start = 0;
    while (start < colorCards.length) {
      var end = start;
      while (end + 1 < colorCards.length &&
          colorCards[end].value == colorCards[end + 1].value + 1) {
        end++;
      }
      if (end - start + 1 >= 5) {
        bombTurns.add(
          TichuTurn(TurnType.bomb, colorCards.sublist(start, end + 1)),
        );
      }
      start = end + 1;
    }
  }
  return bombTurns;
}
