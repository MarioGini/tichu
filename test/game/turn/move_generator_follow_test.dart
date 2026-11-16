import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn/move_generator.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'move_generator_fixtures.dart';

void main() {
  group('generateLegalTurns following a pair', () {
    test('only generates pairs that beat the deck pair', () {
      final hand = [
        Card(CardFace.three, CardColor.red),
        Card(CardFace.three, CardColor.blue),
        Card(CardFace.king, CardColor.green),
        Card(CardFace.king, CardColor.black),
      ];
      final deck = pairDeck(CardFace.five);
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
      final deck = pairDeck(CardFace.two);
      final turns = generateLegalTurns(deck, hand);

      final pairs = turns.where((final t) => t.type == TurnType.pair).toList();
      expect(pairs.length, 3);
    });

    test('dragon plus phoenix does not form a pair', () {
      final hand = [
        Card(CardFace.dragon, CardColor.special),
        Card(CardFace.phoenix, CardColor.special),
      ];
      final deck = pairDeck(CardFace.ace);

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
      final deck = pairDeck(CardFace.two);

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
