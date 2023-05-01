import 'package:test/test.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';
import 'package:tichu/view_model/turn/wish_logic.dart';

void main() {
  group('computeNextWish', () {
    const previousWish = CardFace.ten;
    test('noInputWishTest', () {
      final currentTurn =
          TichuTurn(TurnType.single, [Card(CardFace.eight, Color.blue)]);
      const CardFace inputWish = CardFace.none;

      expect(
          computeNextWish(previousWish, currentTurn, inputWish), previousWish);
    });
    test('inputWishFulfilledTest', () {
      final currentTurn =
          TichuTurn(TurnType.single, [Card(CardFace.ten, Color.blue)]);
      const CardFace inputWish = CardFace.none;

      expect(
          computeNextWish(previousWish, currentTurn, inputWish), CardFace.none);
    });
    test('newInputWishTest', () {
      final currentTurn =
          TichuTurn(TurnType.single, [Card(CardFace.ten, Color.blue)]);
      const inputWish = CardFace.king;

      expect(computeNextWish(CardFace.none, currentTurn, inputWish), inputWish);
    });
  });
  group('haveValidWishBomb', () {
    final cards = [
      Card(CardFace.eight, Color.black),
      Card(CardFace.eight, Color.green),
      Card(CardFace.eight, Color.red),
      Card(CardFace.eight, Color.blue)
    ];
    test('quartetWishBombTest', () {
      var wish = CardFace.eight;
      var turn = TichuTurn(TurnType.single, [Card(CardFace.ten, Color.blue)]);
      var deck = DeckState(turn, wish);

      expect(haveValidWishBomb(deck, cards), true);
    });
    test('noWishBombTest', () {
      var wish = CardFace.eight;
      var turn = TichuTurn(TurnType.bomb, [
        Card(CardFace.nine, Color.black),
        Card(CardFace.nine, Color.green),
        Card(CardFace.nine, Color.red),
        Card(CardFace.nine, Color.blue)
      ]);
      var deck = DeckState(turn, wish);

      expect(haveValidWishBomb(deck, cards), false);
    });
  });
  group('mahJong', () {
    var deckTurn =
        TichuTurn(TurnType.single, [Card(CardFace.eight, Color.black)]);
    test('noWishPresentTest', () {
      var deck = DeckState(deckTurn, CardFace.none);
      var selectedTurn =
          TichuTurn(TurnType.single, [Card(CardFace.king, Color.black)]);
      var cards = <Card>[
        Card(CardFace.four, Color.green),
        Card(CardFace.phoenix, Color.special),
        Card(CardFace.seven, Color.red),
        Card(CardFace.nine, Color.black)
      ];

      expect(mahJong(deck, selectedTurn, cards), false);
    });
    test('wishCardNotAvailableTest', () {
      var deck = DeckState(deckTurn, CardFace.ace);
      var selectedTurn =
          TichuTurn(TurnType.single, [Card(CardFace.king, Color.black)]);
      var cards = <Card>[
        Card(CardFace.four, Color.green),
        Card(CardFace.phoenix, Color.special),
        Card(CardFace.seven, Color.red),
        Card(CardFace.nine, Color.black)
      ];

      expect(mahJong(deck, selectedTurn, cards), false);
    });
    test('wishCardNotAvailableTest', () {
      var deck = DeckState(deckTurn, CardFace.ace);
      var selectedTurn =
          TichuTurn(TurnType.single, [Card(CardFace.ace, Color.black)]);
      var cards = <Card>[
        Card(CardFace.ace, Color.black),
        Card(CardFace.four, Color.green),
        Card(CardFace.phoenix, Color.special),
        Card(CardFace.seven, Color.red),
        Card(CardFace.nine, Color.black)
      ];

      expect(mahJong(deck, selectedTurn, cards), false);
    });
    test('couldPlayWishTest', () {
      var deck = DeckState(deckTurn, CardFace.ace);
      var selectedTurn =
          TichuTurn(TurnType.single, [Card(CardFace.nine, Color.black)]);
      var cards = <Card>[
        Card(CardFace.ace, Color.black),
        Card(CardFace.four, Color.green),
        Card(CardFace.phoenix, Color.special),
        Card(CardFace.seven, Color.red),
        Card(CardFace.nine, Color.black)
      ];

      expect(mahJong(deck, selectedTurn, cards), true);
    });
  });
  group('canPlayWishOnSingle', () {
    final cards = [
      Card(CardFace.four, Color.green),
      Card(CardFace.phoenix, Color.special),
      Card(CardFace.seven, Color.red),
      Card(CardFace.nine, Color.black)
    ];
    final turn = TichuTurn(TurnType.single, [Card(CardFace.five, Color.black)]);
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
    final cards = <Card>[Card(CardFace.nine, Color.red)];
    test('playWishOnDragonTest', () {
      final turn =
          TichuTurn(TurnType.single, [Card(CardFace.dragon, Color.special)]);
      final deck = DeckState(turn, wish);

      expect(cards.any((element) => element.face == wish), true);
      expect(canPlayWish(deck, cards), false);
    });
    test('playWishOnDogTest', () {
      final turn = TichuTurn(TurnType.dog, [Card(CardFace.dog, Color.special)]);
      final deck = DeckState(turn, wish);

      expect(cards.any((element) => element.face == wish), true);
      expect(canPlayWish(deck, cards), true);
    });
  });
  group('canPlayWishOnPair', () {
    final cards = [
      Card(CardFace.five, Color.green),
      Card(CardFace.seven, Color.red),
      Card(CardFace.phoenix, Color.special),
      Card(CardFace.king, Color.black),
      Card(CardFace.king, Color.green)
    ];
    final turn = TichuTurn(TurnType.pair,
        [Card(CardFace.five, Color.red), Card(CardFace.five, Color.black)]);

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
      Card(CardFace.five, Color.green),
      Card(CardFace.seven, Color.red),
      Card(CardFace.nine, Color.red),
      Card(CardFace.jack, Color.red),
      Card(CardFace.jack, Color.green),
      Card(CardFace.phoenix, Color.special),
      Card(CardFace.king, Color.black),
      Card(CardFace.king, Color.green),
      Card(CardFace.king, Color.red)
    ];
    final TichuTurn turn = TichuTurn(TurnType.triplet, [
      Card(CardFace.seven, Color.red),
      Card(CardFace.seven, Color.black),
      Card(CardFace.seven, Color.green)
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
      Card(CardFace.five, Color.green),
      Card(CardFace.phoenix, Color.special),
      Card(CardFace.seven, Color.red),
      Card(CardFace.eight, Color.green),
      Card(CardFace.nine, Color.red),
      Card(CardFace.queen, Color.red)
    ];
    final turn = TichuTurn(TurnType.straight, [
      Card(CardFace.mahJong, Color.special),
      Card(CardFace.two, Color.blue),
      Card(CardFace.three, Color.blue),
      Card(CardFace.four, Color.black),
      Card(CardFace.five, Color.red)
    ]);
    test('canPlayTest', () {
      const wish = CardFace.eight;
      final deck = DeckState(turn, wish);

      expect(canPlayWish(deck, cards), true);
    });
    test('cannotPlayTest', () {
      const wish = CardFace.queen;
      final deck = DeckState(turn, wish);

      expect(canPlayWish(deck, cards), false);
    });
  });
  group('canPlayWishOnPairStraight', () {
    final turn = TichuTurn(TurnType.pairStraight, [
      Card(CardFace.five, Color.red),
      Card(CardFace.five, Color.black),
      Card(CardFace.six, Color.black),
      Card(CardFace.six, Color.green)
    ]);
    test('cannotPlayTest', () {
      const wish = CardFace.eight;
      final cards = <Card>[
        Card(CardFace.eight, Color.red),
        Card(CardFace.eight, Color.black),
        Card(CardFace.nine, Color.red),
        Card(CardFace.phoenix, Color.special)
      ];
      final deck = DeckState(turn, wish);

      expect(cards.any((card) => card.face == wish), true);
      expect(canPlayWish(deck, cards), true);
    });
  });
  group('canPlayWishOnFullHouse', () {
    const wish = CardFace.nine;
    final TichuTurn turn = TichuTurn(TurnType.fullHouse, [
      Card(CardFace.seven, Color.red),
      Card(CardFace.seven, Color.black),
      Card(CardFace.seven, Color.green),
      Card(CardFace.five, Color.green),
      Card(CardFace.five, Color.red)
    ]);
    test('cannotPlayTripletAndPhoenix', () {
      final cards = <Card>[
        Card(CardFace.nine, Color.red),
        Card(CardFace.nine, Color.black),
        Card(CardFace.nine, Color.green),
        Card(CardFace.phoenix, Color.special)
      ];
      final deck = DeckState(turn, wish);

      expect(cards.any((card) => card.face == wish), true);
      expect(canPlayWish(deck, cards), false);
    });
    test('canPlayTripletSingleAndPhoenix', () {
      final cards = <Card>[
        Card(CardFace.eight, Color.red),
        Card(CardFace.eight, Color.black),
        Card(CardFace.eight, Color.green),
        Card(CardFace.nine, Color.green),
        Card(CardFace.jack, Color.green),
        Card(CardFace.phoenix, Color.special)
      ];
      final deck = DeckState(turn, wish);

      expect(cards.any((element) => element.face == wish), true);
      expect(canPlayWish(deck, cards), true);
    });
    test('canPlayTwoPairsAndPhoenix', () {
      final cards = <Card>[
        Card(CardFace.nine, Color.green),
        Card(CardFace.nine, Color.black),
        Card(CardFace.jack, Color.green),
        Card(CardFace.jack, Color.black),
        Card(CardFace.phoenix, Color.special)
      ];
      final deck = DeckState(turn, wish);

      expect(cards.any((element) => element.face == wish), true);
      expect(canPlayWish(deck, cards), true);
    });
    test('canPlayWithoutPhoenix', () {
      final cards = <Card>[
        Card(CardFace.nine, Color.green),
        Card(CardFace.nine, Color.black),
        Card(CardFace.nine, Color.red),
        Card(CardFace.jack, Color.green),
        Card(CardFace.jack, Color.black),
        Card(CardFace.six, Color.red)
      ];
      final deck = DeckState(turn, wish);

      expect(cards.any((element) => element.face == wish), true);
      expect(canPlayWish(deck, cards), true);
    });
    test('cannotPlayWithoutPhoenix', () {
      final cards = <Card>[
        Card(CardFace.nine, Color.green),
        Card(CardFace.nine, Color.black),
        Card(CardFace.jack, Color.green),
        Card(CardFace.jack, Color.black),
        Card(CardFace.six, Color.red)
      ];
      final deck = DeckState(turn, wish);

      expect(cards.any((element) => element.face == wish), true);
      expect(canPlayWish(deck, cards), false);
    });
  });
}
