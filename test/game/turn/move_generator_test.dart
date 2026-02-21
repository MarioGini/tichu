import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn/move_generator.dart';
import 'package:tichu/game/turn/tichu_data.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

DeckState _emptyDeck() =>
    DeckState(TichuTurn(TurnType.empty, const []), CardFace.none);

DeckState _singleDeck(final CardFace face) {
  final deck = DeckState(
    TichuTurn(TurnType.single, [Card(face, CardColor.red)]),
    CardFace.none,
  );
  deck.currentWinner = 'other';
  return deck;
}

DeckState _pairDeck(final CardFace face) {
  final deck = DeckState(
    TichuTurn(TurnType.pair, [
      Card(face, CardColor.red),
      Card(face, CardColor.blue),
    ]),
    CardFace.none,
  );
  deck.currentWinner = 'other';
  return deck;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('generateLegalTurns on empty deck', () {
    test('empty hand produces no turns', () {
      final turns = generateLegalTurns(_emptyDeck(), []);
      expect(turns, isEmpty);
    });

    test('single card produces one single turn', () {
      final hand = [Card(CardFace.five, CardColor.red)];
      final turns = generateLegalTurns(_emptyDeck(), hand);

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
      final turns = generateLegalTurns(_emptyDeck(), hand);

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
      final turns = generateLegalTurns(_emptyDeck(), hand);

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
      final turns = generateLegalTurns(_emptyDeck(), hand);

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
      final turns = generateLegalTurns(_emptyDeck(), hand);

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
      final turns = generateLegalTurns(_emptyDeck(), hand);

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
      final turns = generateLegalTurns(_emptyDeck(), hand);

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
      final turns = generateLegalTurns(_emptyDeck(), hand);

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
      final turns = generateLegalTurns(_emptyDeck(), hand);

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
      final turns = generateLegalTurns(_emptyDeck(), hand);

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
      final deck = _singleDeck(CardFace.five);
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
      final deck = _singleDeck(CardFace.ace);
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
      final deck = _singleDeck(CardFace.ace);
      final turns = generateLegalTurns(deck, hand);

      // No singles beat the ace, no bombs available.
      expect(turns, isEmpty);
    });
  });

  group('generateLegalTurns following a pair', () {
    test('only generates pairs that beat the deck pair', () {
      final hand = [
        Card(CardFace.three, CardColor.red),
        Card(CardFace.three, CardColor.blue),
        Card(CardFace.king, CardColor.green),
        Card(CardFace.king, CardColor.black),
      ];
      final deck = _pairDeck(CardFace.five);
      final turns = generateLegalTurns(deck, hand);

      final pairs = turns.where((final t) => t.type == TurnType.pair).toList();
      // Pair of 3s doesn't beat pair of 5s. Only kings should show.
      expect(pairs.length, 1);
      expect(pairs.first.cards.first.face, CardFace.king);
    });

    test('three-of-a-kind yields all selectable pairs', () {
      final hand = [
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.ace, CardColor.blue),
        Card(CardFace.ace, CardColor.green),
      ];
      final deck = _pairDeck(CardFace.two);
      final turns = generateLegalTurns(deck, hand);

      final pairs = turns.where((final t) => t.type == TurnType.pair).toList();
      expect(pairs.length, 3);
    });

    test('dragon plus phoenix does not form a pair', () {
      final hand = [
        Card(CardFace.dragon, CardColor.special),
        Card(CardFace.phoenix, CardColor.special),
      ];
      final deck = _pairDeck(CardFace.ace);

      final turns = generateLegalTurns(deck, hand);
      final dragonPairs = turns.where(
        (final t) =>
            t.type == TurnType.pair &&
            t.cards.any((final c) => c.face == CardFace.dragon) &&
            t.cards.any((final c) => c.face == CardFace.phoenix),
      );

      expect(dragonPairs, isEmpty);
      expect(turns, isEmpty);
    });

    test('mahjong plus phoenix does not form a pair', () {
      final hand = [
        Card(CardFace.mahJong, CardColor.special),
        Card(CardFace.phoenix, CardColor.special),
      ];
      final deck = _pairDeck(CardFace.two);

      final turns = generateLegalTurns(deck, hand);
      final mahjongPairs = turns.where(
        (final t) =>
            t.type == TurnType.pair &&
            t.cards.any((final c) => c.face == CardFace.mahJong) &&
            t.cards.any((final c) => c.face == CardFace.phoenix),
      );

      expect(mahjongPairs, isEmpty);
      expect(turns, isEmpty);
    });
  });

  group('generateLegalTurns with dog deck', () {
    test('dog deck allows any opening play', () {
      final hand = [
        Card(CardFace.five, CardColor.red),
        Card(CardFace.ten, CardColor.blue),
      ];
      final dogDeck = DeckState(
        TichuTurn(TurnType.dog, [Card(CardFace.dog, CardColor.special)]),
        CardFace.none,
      );
      final turns = generateLegalTurns(dogDeck, hand);

      // Should generate all possible plays, not just those that beat "dog".
      expect(turns, isNotEmpty);
    });
  });

  group('generateLegalTurns on advanced trick types', () {
    test('straight deck only allows same-length higher straight or bombs', () {
      final hand = [
        Card(CardFace.five, CardColor.red),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.seven, CardColor.green),
        Card(CardFace.eight, CardColor.black),
        Card(CardFace.nine, CardColor.red),
        Card(CardFace.ten, CardColor.blue),
      ];
      final deck = DeckState(
        TichuTurn(TurnType.straight, [
          Card(CardFace.four, CardColor.red),
          Card(CardFace.five, CardColor.blue),
          Card(CardFace.six, CardColor.green),
          Card(CardFace.seven, CardColor.black),
          Card(CardFace.eight, CardColor.red),
        ]),
        CardFace.none,
      );

      final turns = generateLegalTurns(deck, hand);
      expect(
        turns.any(
          (final t) => t.type == TurnType.straight && t.cards.length == 5,
        ),
        isTrue,
      );
    });

    test('pair-straight deck generates valid pair-straight responses', () {
      final hand = [
        Card(CardFace.six, CardColor.red),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.seven, CardColor.blue),
        Card(CardFace.eight, CardColor.red),
        Card(CardFace.eight, CardColor.blue),
      ];
      final deck = DeckState(
        TichuTurn(TurnType.pairStraight, [
          Card(CardFace.four, CardColor.red),
          Card(CardFace.four, CardColor.blue),
          Card(CardFace.five, CardColor.red),
          Card(CardFace.five, CardColor.blue),
        ]),
        CardFace.none,
      );

      final turns = generateLegalTurns(deck, hand);
      expect(turns.any((final t) => t.type == TurnType.pairStraight), isTrue);
    });

    test('full-house deck generates valid full-house responses', () {
      final hand = [
        Card(CardFace.six, CardColor.red),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.six, CardColor.green),
        Card(CardFace.nine, CardColor.red),
        Card(CardFace.nine, CardColor.blue),
      ];
      final deck = DeckState(
        TichuTurn(TurnType.fullHouse, [
          Card(CardFace.five, CardColor.red),
          Card(CardFace.five, CardColor.blue),
          Card(CardFace.five, CardColor.green),
          Card(CardFace.seven, CardColor.red),
          Card(CardFace.seven, CardColor.blue),
        ]),
        CardFace.none,
      );

      final turns = generateLegalTurns(deck, hand);
      expect(turns.any((final t) => t.type == TurnType.fullHouse), isTrue);
    });

    test('bomb deck only allows stronger bombs', () {
      final hand = [
        Card(CardFace.nine, CardColor.red),
        Card(CardFace.nine, CardColor.blue),
        Card(CardFace.nine, CardColor.green),
        Card(CardFace.nine, CardColor.black),
      ];
      final deck = DeckState(
        TichuTurn(TurnType.bomb, [
          Card(CardFace.five, CardColor.red),
          Card(CardFace.five, CardColor.blue),
          Card(CardFace.five, CardColor.green),
          Card(CardFace.five, CardColor.black),
        ]),
        CardFace.none,
      );

      final turns = generateLegalTurns(deck, hand);
      expect(turns, hasLength(1));
      expect(turns.first.type, TurnType.bomb);
    });

    test('phoenix cannot be played over dragon single', () {
      final hand = [
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.two, CardColor.red),
      ];
      final deck = DeckState(
        TichuTurn(TurnType.single, [Card(CardFace.dragon, CardColor.special)]),
        CardFace.none,
      );

      final turns = generateLegalTurns(deck, hand);
      expect(turns.where((final t) => t.type == TurnType.single), isEmpty);
    });
  });
}
