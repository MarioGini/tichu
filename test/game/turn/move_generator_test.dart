import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/card_identifiers.dart';
import 'package:tichu/game/turn/move_generator.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/pair_straight_utils.dart';
import 'package:tichu/game/turn/utils/straight_utils.dart';

import 'move_generator_fixtures.dart';

void main() {
  group('generateLegalTurns on empty deck', () {
    test('empty hand produces no turns', () {
      final turns = generateLegalTurns(emptyDeck(), []);
      expect(turns, isEmpty);
    });

    test('single card produces one single turn', () {
      final hand = [Card(CardFace.five, CardColor.red)];
      final turns = generateLegalTurns(emptyDeck(), hand);

      final singles = turns
          .where((final t) => t.type == TurnType.single)
          .toList();
      expect(singles.length, 1);
      expect(singles.first.cards.first.face, CardFace.five);
    });

    test('pair in hand generates pair turn', () {
      final hand = [
        Card(CardFace.eight, CardColor.red),
        Card(CardFace.eight, CardColor.blue),
      ];
      final turns = generateLegalTurns(emptyDeck(), hand);

      final pairs = turns.where((final t) => t.type == TurnType.pair).toList();
      expect(pairs.length, 1);
      expect(pairs.first.cards.length, 2);
    });

    test('triplet in hand generates triplet turn', () {
      final hand = [
        Card(CardFace.ten, CardColor.red),
        Card(CardFace.ten, CardColor.blue),
        Card(CardFace.ten, CardColor.green),
      ];
      final turns = generateLegalTurns(emptyDeck(), hand);

      final triplets = turns
          .where((final t) => t.type == TurnType.triplet)
          .toList();
      expect(triplets.length, 1);
      expect(triplets.first.cards.length, 3);
    });

    test('four of a kind generates bomb', () {
      final hand = [
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.seven, CardColor.blue),
        Card(CardFace.seven, CardColor.green),
        Card(CardFace.seven, CardColor.black),
      ];
      final turns = generateLegalTurns(emptyDeck(), hand);

      final bombs = turns.where((final t) => t.type == TurnType.bomb).toList();
      expect(bombs, isNotEmpty);
    });

    test('five-card sequence generates straight', () {
      final hand = [
        Card(CardFace.four, CardColor.red),
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.six, CardColor.green),
        Card(CardFace.seven, CardColor.black),
        Card(CardFace.eight, CardColor.red),
      ];
      final turns = generateLegalTurns(emptyDeck(), hand);

      final straights = turns
          .where((final t) => t.type == TurnType.straight)
          .toList();
      expect(straights, isNotEmpty);
      expect(straights.first.cards.length, 5);
    });

    test('stairs (pair straight) of length 8 is generated', () {
      final hand = [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.two, CardColor.blue),
        Card(CardFace.three, CardColor.red),
        Card(CardFace.three, CardColor.blue),
        Card(CardFace.four, CardColor.red),
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.five, CardColor.blue),
      ];
      final turns = generateLegalTurns(emptyDeck(), hand);

      final stairs = turns
          .where(
            (final t) => t.type == TurnType.pairStraight && t.cards.length == 8,
          )
          .toList();
      expect(stairs, isNotEmpty);
    });

    test('phoenix completes 1234 into a straight', () {
      final hand = [
        Card(CardFace.mahJong, CardColor.special),
        Card(CardFace.two, CardColor.red),
        Card(CardFace.three, CardColor.blue),
        Card(CardFace.four, CardColor.green),
        Card(CardFace.phoenix, CardColor.special),
      ];
      final turns = generateLegalTurns(emptyDeck(), hand);

      final straights = turns
          .where(
            (final t) => t.type == TurnType.straight && t.cards.length == 5,
          )
          .toList();
      expect(straights, isNotEmpty);
    });

    test('phoenix extends 123456 into a 7-card straight', () {
      final hand = [
        Card(CardFace.mahJong, CardColor.special),
        Card(CardFace.two, CardColor.red),
        Card(CardFace.three, CardColor.blue),
        Card(CardFace.four, CardColor.green),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.phoenix, CardColor.special),
      ];
      final turns = generateLegalTurns(emptyDeck(), hand);

      final straights = turns
          .where(
            (final t) => t.type == TurnType.straight && t.cards.length == 7,
          )
          .toList();
      expect(straights, isNotEmpty);
    });

    test('phoenix fills the gap in 12356 into a straight', () {
      final hand = [
        Card(CardFace.mahJong, CardColor.special),
        Card(CardFace.two, CardColor.red),
        Card(CardFace.three, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.six, CardColor.red),
        Card(CardFace.phoenix, CardColor.special),
      ];
      final turns = generateLegalTurns(emptyDeck(), hand);

      final straights = turns
          .where(
            (final t) => t.type == TurnType.straight && t.cards.length == 6,
          )
          .toList();
      expect(straights, isNotEmpty);
    });

    test('phoenix creates extra plays', () {
      final hand = [
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.five, CardColor.red),
      ];
      final turns = generateLegalTurns(emptyDeck(), hand);

      // Should include: single 5, single phoenix, pair (5 + phoenix)
      final singles = turns
          .where((final t) => t.type == TurnType.single)
          .toList();
      final pairs = turns.where((final t) => t.type == TurnType.pair).toList();
      expect(singles.length, 2); // 5 and phoenix
      expect(pairs.length, 1); // 5 + phoenix pair
    });
  });

  group('generateLegalTurns following a single', () {
    test('only generates singles that beat the deck', () {
      final hand = [
        Card(CardFace.three, CardColor.red),
        Card(CardFace.eight, CardColor.blue),
        Card(CardFace.king, CardColor.green),
      ];
      final deck = singleDeck(CardFace.five);
      final turns = generateLegalTurns(deck, hand);

      for (final turn in turns) {
        if (turn.type == TurnType.single) {
          expect(turn.value, greaterThan(5));
        }
      }

      // 3 doesn't beat 5, so only 8 and king should appear as singles.
      final singles = turns
          .where((final t) => t.type == TurnType.single)
          .toList();
      expect(singles.length, 2);
    });

    test('bombs are always available regardless of deck type', () {
      final hand = [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.two, CardColor.blue),
        Card(CardFace.two, CardColor.green),
        Card(CardFace.two, CardColor.black),
      ];
      final deck = singleDeck(CardFace.ace);
      final turns = generateLegalTurns(deck, hand);

      // Can't beat ace with any single 2, but the 4-of-a-kind bomb is valid.
      final bombs = turns.where((final t) => t.type == TurnType.bomb).toList();
      expect(bombs, isNotEmpty);
    });

    test('returns empty when no play can beat the deck', () {
      final hand = [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.three, CardColor.blue),
      ];
      final deck = singleDeck(CardFace.ace);
      final turns = generateLegalTurns(deck, hand);

      // No singles beat the ace, no bombs available.
      expect(turns, isEmpty);
    });
  });

  // Leads build the straight candidates once for all lengths; the result
  // must be getStraights / getPairStraights for each length, in order.
  test('lead straights equal the per-length searches', () {
    final deck = cardIdentifiers.values.toList();
    final rng = Random(4);
    for (var i = 0; i < 3000; i++) {
      final hand = (deck.toList()..shuffle(rng)).take(5 + rng.nextInt(10));
      final h = hand.toList();
      final turns = generateLegalTurns(emptyDeck(), h);
      String key(final TichuTurn t) => '${t.value}:${t.cards.length}';
      expect(
        [
          for (final t in turns)
            if (t.type == TurnType.straight) key(t),
        ],
        [
          for (var n = 5; n <= h.length; n++)
            for (final t in getStraights(h, n)) key(t),
        ],
      );
      expect(
        [
          for (final t in turns)
            if (t.type == TurnType.pairStraight) key(t),
        ],
        [
          for (var n = 4; n <= h.length; n += 2)
            for (final t in getPairStraights(h, n)) key(t),
        ],
      );
    }
  });
}
