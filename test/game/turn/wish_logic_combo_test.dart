import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/wish_logic.dart';

void main() {
  group('canPlayWishOnTriplet', () {
    final cards = [
      Card(CardFace.five, CardColor.green),
      Card(CardFace.seven, CardColor.red),
      Card(CardFace.nine, CardColor.red),
      Card(CardFace.jack, CardColor.red),
      Card(CardFace.jack, CardColor.green),
      Card(CardFace.phoenix, CardColor.special),
      Card(CardFace.king, CardColor.black),
      Card(CardFace.king, CardColor.green),
      Card(CardFace.king, CardColor.red),
    ];
    final turn = TichuTurn(TurnType.triplet, [
      Card(CardFace.seven, CardColor.red),
      Card(CardFace.seven, CardColor.black),
      Card(CardFace.seven, CardColor.green),
    ]);
    test('cannotPlayTest', () {
      // We have only one nine and cannot fulfill wish.
      const wish = CardFace.nine;
      final deck = DeckState(turn, wish);

      expect(cards.any((element) => element.face == wish), true);
      expect(canPlayWish(deck, cards), false);
    });
    test('canPlayTest', () {
      // We have three kings on the hand and can fulfill wish.
      const wish = CardFace.king;
      final deck = DeckState(turn, wish);

      expect(cards.any((element) => element.face == wish), true);
      expect(canPlayWish(deck, cards), true);
    });
    test('canPlayWithPhoenixTest', () {
      // We have two jacks and the phoenix on the hand and can fulfill wish.
      const wish = CardFace.jack;
      final deck = DeckState(turn, wish);

      expect(cards.any((element) => element.face == wish), true);
      expect(canPlayWish(deck, cards), true);
    });
  });
  group('canPlayWishOnStraight', () {
    final cards = <Card>[
      Card(CardFace.five, CardColor.green),
      Card(CardFace.phoenix, CardColor.special),
      Card(CardFace.seven, CardColor.red),
      Card(CardFace.eight, CardColor.green),
      Card(CardFace.nine, CardColor.red),
      Card(CardFace.queen, CardColor.red),
    ];
    final turn = TichuTurn(TurnType.straight, [
      Card(CardFace.mahJong, CardColor.special),
      Card(CardFace.two, CardColor.blue),
      Card(CardFace.three, CardColor.blue),
      Card(CardFace.four, CardColor.black),
      Card(CardFace.five, CardColor.red),
    ]);
    test('canPlayTest', () {
      const wish = CardFace.eight;
      final deck = DeckState(turn, wish);

      expect(canPlayWish(deck, cards), true);
    });
    test('canPlayWithPhoenixGapTest', () {
      const wish = CardFace.seven;
      final deckTurn = TichuTurn(TurnType.straight, [
        Card(CardFace.three, CardColor.red),
        Card(CardFace.four, CardColor.green),
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.six, CardColor.black),
        Card(CardFace.seven, CardColor.red),
      ]);
      final deck = DeckState(deckTurn, wish);
      final phoenixGapCards = <Card>[
        Card(CardFace.five, CardColor.green),
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.eight, CardColor.green),
        Card(CardFace.nine, CardColor.red),
        Card(CardFace.phoenix, CardColor.special),
      ];

      expect(canPlayWish(deck, phoenixGapCards), true);
    });
    test('cannotPlayTest', () {
      const wish = CardFace.queen;
      final deck = DeckState(turn, wish);

      expect(canPlayWish(deck, cards), false);
    });
  });
  group('canPlayWishOnPairStraight', () {
    final turn = TichuTurn(TurnType.pairStraight, [
      Card(CardFace.five, CardColor.red),
      Card(CardFace.five, CardColor.black),
      Card(CardFace.six, CardColor.black),
      Card(CardFace.six, CardColor.green),
    ]);
    test('canPlayWithPhoenixPairStraight', () {
      const wish = CardFace.eight;
      final cards = <Card>[
        Card(CardFace.eight, CardColor.red),
        Card(CardFace.eight, CardColor.black),
        Card(CardFace.nine, CardColor.red),
        Card(CardFace.phoenix, CardColor.special),
      ];
      final deck = DeckState(turn, wish);

      expect(cards.any((card) => card.face == wish), true);
      expect(canPlayWish(deck, cards), true);
    });
  });
  group('canPlayWishOnFullHouse', () {
    const wish = CardFace.nine;
    final turn = TichuTurn(TurnType.fullHouse, [
      Card(CardFace.seven, CardColor.red),
      Card(CardFace.seven, CardColor.black),
      Card(CardFace.seven, CardColor.green),
      Card(CardFace.five, CardColor.green),
      Card(CardFace.five, CardColor.red),
    ]);
    test('cannotPlayTripletAndPhoenix', () {
      final cards = <Card>[
        Card(CardFace.nine, CardColor.red),
        Card(CardFace.nine, CardColor.black),
        Card(CardFace.nine, CardColor.green),
        Card(CardFace.phoenix, CardColor.special),
      ];
      final deck = DeckState(turn, wish);

      expect(cards.any((card) => card.face == wish), true);
      expect(canPlayWish(deck, cards), false);
    });
    test('canPlayTripletSingleAndPhoenix', () {
      final cards = <Card>[
        Card(CardFace.eight, CardColor.red),
        Card(CardFace.eight, CardColor.black),
        Card(CardFace.eight, CardColor.green),
        Card(CardFace.nine, CardColor.green),
        Card(CardFace.jack, CardColor.green),
        Card(CardFace.phoenix, CardColor.special),
      ];
      final deck = DeckState(turn, wish);

      expect(cards.any((element) => element.face == wish), true);
      expect(canPlayWish(deck, cards), true);
    });
    test('canPlayTwoPairsAndPhoenix', () {
      final cards = <Card>[
        Card(CardFace.nine, CardColor.green),
        Card(CardFace.nine, CardColor.black),
        Card(CardFace.jack, CardColor.green),
        Card(CardFace.jack, CardColor.black),
        Card(CardFace.phoenix, CardColor.special),
      ];
      final deck = DeckState(turn, wish);

      expect(cards.any((element) => element.face == wish), true);
      expect(canPlayWish(deck, cards), true);
    });
    test('canPlayWithoutPhoenix', () {
      final cards = <Card>[
        Card(CardFace.nine, CardColor.green),
        Card(CardFace.nine, CardColor.black),
        Card(CardFace.nine, CardColor.red),
        Card(CardFace.jack, CardColor.green),
        Card(CardFace.jack, CardColor.black),
        Card(CardFace.six, CardColor.red),
      ];
      final deck = DeckState(turn, wish);

      expect(cards.any((element) => element.face == wish), true);
      expect(canPlayWish(deck, cards), true);
    });
    test('cannotPlayWithoutPhoenix', () {
      final cards = <Card>[
        Card(CardFace.nine, CardColor.green),
        Card(CardFace.nine, CardColor.black),
        Card(CardFace.jack, CardColor.green),
        Card(CardFace.jack, CardColor.black),
        Card(CardFace.six, CardColor.red),
      ];
      final deck = DeckState(turn, wish);

      expect(cards.any((element) => element.face == wish), true);
      expect(canPlayWish(deck, cards), false);
    });
  });

  group('isWishableFace', () {
    test('accepts standard card faces', () {
      expect(isWishableFace(CardFace.ace), isTrue);
      expect(isWishableFace(CardFace.two), isTrue);
      expect(isWishableFace(CardFace.ten), isTrue);
    });

    test('rejects special faces', () {
      expect(isWishableFace(CardFace.dragon), isFalse);
      expect(isWishableFace(CardFace.phoenix), isFalse);
      expect(isWishableFace(CardFace.dog), isFalse);
      expect(isWishableFace(CardFace.mahJong), isFalse);
      expect(isWishableFace(CardFace.none), isFalse);
    });
  });

  group('defaultWishFaceFromSchupf', () {
    test('uses the card schupfed to opponent 1 (toLeft)', () {
      final wish = defaultWishFaceFromSchupf(
        toLeft: Card(CardFace.three, CardColor.red),
        toPartner: Card(CardFace.jack, CardColor.blue),
        toRight: Card(CardFace.ace, CardColor.green),
      );
      expect(wish, CardFace.three);
    });

    test('returns null when no opponent 1 schupf card', () {
      final wish = defaultWishFaceFromSchupf(
        toLeft: null,
        toPartner: Card(CardFace.ten, CardColor.red),
        toRight: Card(CardFace.king, CardColor.black),
      );
      expect(wish, isNull);
    });
  });
}
