import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/wish_logic.dart';

void main() {
  group('computeNextWish', () {
    const previousWish = CardFace.ten;
    test('noInputWishTest', () {
      final currentTurn = TichuTurn(TurnType.single, [
        Card(CardFace.eight, CardColor.blue),
      ]);
      const CardFace inputWish = CardFace.none;

      expect(
        computeNextWish(previousWish, currentTurn, inputWish),
        previousWish,
      );
    });
    test('inputWishFulfilledTest', () {
      final currentTurn = TichuTurn(TurnType.single, [
        Card(CardFace.ten, CardColor.blue),
      ]);
      const CardFace inputWish = CardFace.none;

      expect(
        computeNextWish(previousWish, currentTurn, inputWish),
        CardFace.none,
      );
    });
    test('newInputWishTest', () {
      final currentTurn = TichuTurn(TurnType.single, [
        Card(CardFace.ten, CardColor.blue),
      ]);
      const inputWish = CardFace.king;

      expect(computeNextWish(CardFace.none, currentTurn, inputWish), inputWish);
    });
  });
  group('haveValidWishBomb', () {
    final cards = [
      Card(CardFace.eight, CardColor.black),
      Card(CardFace.eight, CardColor.green),
      Card(CardFace.eight, CardColor.red),
      Card(CardFace.eight, CardColor.blue),
    ];
    test('quartetWishBombTest', () {
      var wish = CardFace.eight;
      var turn = TichuTurn(TurnType.single, [
        Card(CardFace.ten, CardColor.blue),
      ]);
      var deck = DeckState(turn, wish);

      expect(haveValidWishBomb(deck, cards), true);
    });
    test('noWishBombTest', () {
      var wish = CardFace.eight;
      var turn = TichuTurn(TurnType.bomb, [
        Card(CardFace.nine, CardColor.black),
        Card(CardFace.nine, CardColor.green),
        Card(CardFace.nine, CardColor.red),
        Card(CardFace.nine, CardColor.blue),
      ]);
      var deck = DeckState(turn, wish);

      expect(haveValidWishBomb(deck, cards), false);
    });
  });
  group('mahJong', () {
    var deckTurn = TichuTurn(TurnType.single, [
      Card(CardFace.eight, CardColor.black),
    ]);
    test('noWishPresentTest', () {
      var deck = DeckState(deckTurn, CardFace.none);
      var selectedTurn = TichuTurn(TurnType.single, [
        Card(CardFace.king, CardColor.black),
      ]);
      var cards = <Card>[
        Card(CardFace.four, CardColor.green),
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.nine, CardColor.black),
      ];

      expect(mahJong(deck, selectedTurn, cards), false);
    });
    test('wishCardNotAvailableTest', () {
      var deck = DeckState(deckTurn, CardFace.ace);
      var selectedTurn = TichuTurn(TurnType.single, [
        Card(CardFace.king, CardColor.black),
      ]);
      var cards = <Card>[
        Card(CardFace.four, CardColor.green),
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.nine, CardColor.black),
      ];

      expect(mahJong(deck, selectedTurn, cards), false);
    });
    test('wishFulfilledBySelectedTurn', () {
      var deck = DeckState(deckTurn, CardFace.ace);
      var selectedTurn = TichuTurn(TurnType.single, [
        Card(CardFace.ace, CardColor.black),
      ]);
      var cards = <Card>[
        Card(CardFace.ace, CardColor.black),
        Card(CardFace.four, CardColor.green),
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.nine, CardColor.black),
      ];

      expect(mahJong(deck, selectedTurn, cards), false);
    });
    test('couldPlayWishTest', () {
      var deck = DeckState(deckTurn, CardFace.ace);
      var selectedTurn = TichuTurn(TurnType.single, [
        Card(CardFace.nine, CardColor.black),
      ]);
      var cards = <Card>[
        Card(CardFace.ace, CardColor.black),
        Card(CardFace.four, CardColor.green),
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.nine, CardColor.black),
      ];

      expect(mahJong(deck, selectedTurn, cards), true);
    });
  });
  group('canPlayWishOnSingle', () {
    final cards = [
      Card(CardFace.four, CardColor.green),
      Card(CardFace.phoenix, CardColor.special),
      Card(CardFace.seven, CardColor.red),
      Card(CardFace.nine, CardColor.black),
    ];
    final turn = TichuTurn(TurnType.single, [
      Card(CardFace.five, CardColor.black),
    ]);
    test('cannotPlayTest', () {
      const wish = CardFace.four;
      final deck = DeckState(turn, wish);

      // The wish is lower than currently played card.
      expect(cards.any((element) => element.face == wish), true);
      expect(canPlayWish(deck, cards), false);
    });
    test('canPlayTest', () {
      const wish = CardFace.nine;
      final deck = DeckState(turn, wish);

      // The wish is higher than deck value and can be played.
      expect(cards.any((element) => element.face == wish), true);
      expect(canPlayWish(deck, cards), true);
    });
  });
  group('canPlayWishSpecialTurnTypes', () {
    const wish = CardFace.nine;
    final cards = <Card>[Card(CardFace.nine, CardColor.red)];
    test('playWishOnDragonTest', () {
      final turn = TichuTurn(TurnType.single, [
        Card(CardFace.dragon, CardColor.special),
      ]);
      final deck = DeckState(turn, wish);

      expect(cards.any((element) => element.face == wish), true);
      expect(canPlayWish(deck, cards), false);
    });
    test('playWishOnDogTest', () {
      final turn = TichuTurn(TurnType.dog, [
        Card(CardFace.dog, CardColor.special),
      ]);
      final deck = DeckState(turn, wish);

      expect(cards.any((element) => element.face == wish), true);
      expect(canPlayWish(deck, cards), true);
    });
  });
  group('canPlayWishOnPair', () {
    final cards = [
      Card(CardFace.five, CardColor.green),
      Card(CardFace.seven, CardColor.red),
      Card(CardFace.phoenix, CardColor.special),
      Card(CardFace.king, CardColor.black),
      Card(CardFace.king, CardColor.green),
    ];
    final turn = TichuTurn(TurnType.pair, [
      Card(CardFace.five, CardColor.red),
      Card(CardFace.five, CardColor.black),
    ]);

    test('cannotPlayTest', () {
      // The wish has the same value as the current deck so it cannot be
      // fulfilled.
      const wish = CardFace.five;
      final deck = DeckState(turn, wish);

      expect(cards.any((element) => element.face == wish), true);
      expect(canPlayWish(deck, cards), false);
    });
    test('canPlayTest', () {
      // We have two kings on our hand so wish can be fulfilled.
      const wish = CardFace.king;
      final deck = DeckState(turn, wish);

      expect(cards.any((element) => element.face == wish), true);
      expect(canPlayWish(deck, cards), true);
    });
    test('canPlayWithPhoenixTest', () {
      // The wish can be fulfilled by using the phoenix to form a pair.
      const wish = CardFace.seven;
      final deck = DeckState(turn, wish);

      expect(cards.any((element) => element.face == wish), true);
      expect(canPlayWish(deck, cards), true);
    });
  });
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
    final TichuTurn turn = TichuTurn(TurnType.triplet, [
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
    final TichuTurn turn = TichuTurn(TurnType.fullHouse, [
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
}
