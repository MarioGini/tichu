import 'package:test/test.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';
import 'package:tichu/view_model/turn/wish_logic.dart';

void main() {
  group('computeNextWish', () {
    var previousWish = CardFace.ten;
    test('noInputWishTest', () {
      var currentTurn =
          TichuTurn(TurnType.single, [Card(CardFace.eight, Color.blue)]);
      CardFace inputWish;

      expect(
          computeNextWish(previousWish, currentTurn, inputWish), previousWish);
    });
    test('inputWishFulfilledTest', () {
      var currentTurn =
          TichuTurn(TurnType.single, [Card(CardFace.ten, Color.blue)]);
      CardFace inputWish;

      expect(computeNextWish(previousWish, currentTurn, inputWish), null);
    });
    test('newInputWishTest', () {
      previousWish = null;
      var currentTurn =
          TichuTurn(TurnType.single, [Card(CardFace.ten, Color.blue)]);
      var inputWish = CardFace.king;

      expect(computeNextWish(previousWish, currentTurn, inputWish), inputWish);
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
      var deck = DeckState(deckTurn, null);
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
    List<Card> cards;
    TichuTurn turn;
    setUp(() {
      turn = TichuTurn(TurnType.single, [Card(CardFace.five, Color.black)]);
      cards = [
        Card(CardFace.four, Color.green),
        Card(CardFace.phoenix, Color.special),
        Card(CardFace.seven, Color.red),
        Card(CardFace.nine, Color.black)
      ];
    });
    test('cannotPlayTest', () {
      // Make sure that wish card is contained in cards which is assumption of
      // function below.
      var wish = CardFace.four;
      expect(cards.any((element) => element.face == wish), true);
      var deck = DeckState(turn, wish);

      // The wish is lower than currently played card.
      expect(canPlayWish(deck, cards), false);
    });
    test('canPlayTest', () {
      // Make sure that wish card is contained in cards which is assumption of
      // function below.
      var wish = CardFace.nine;
      expect(cards.any((element) => element.face == wish), true);
      var deck = DeckState(turn, wish);

      // The wish is higher than deck value and can be played.
      expect(canPlayWish(deck, cards), true);
    });
  });
  group('canPlayWishSpecialTurnTypes', () {
    test('playWishOnDragonTest', () {
      var turn =
          TichuTurn(TurnType.single, [Card(CardFace.dragon, Color.special)]);
      var wish = CardFace.nine;
      var cards = <Card>[Card(CardFace.nine, Color.red)];
      var deck = DeckState(turn, wish);
      expect(cards.any((element) => element.face == wish), true);

      expect(canPlayWish(deck, cards), false);
    });
    test('playWishOnDogTest', () {
      var turn = TichuTurn(TurnType.dog, [Card(CardFace.dog, Color.special)]);
      var wish = CardFace.nine;
      var cards = <Card>[Card(CardFace.nine, Color.red)];
      var deck = DeckState(turn, wish);
      expect(cards.any((element) => element.face == wish), true);

      expect(canPlayWish(deck, cards), true);
    });
  });
  group('canPlayWishOnPair', () {
    List<Card> cards;
    TichuTurn turn;
    setUp(() {
      cards = [
        Card(CardFace.five, Color.green),
        Card(CardFace.seven, Color.red),
        Card(CardFace.phoenix, Color.special),
        Card(CardFace.king, Color.black),
        Card(CardFace.king, Color.green)
      ];
      turn = TichuTurn(TurnType.pair,
          [Card(CardFace.five, Color.red), Card(CardFace.five, Color.black)]);
    });
    test('cannotPlayTest', () {
      // The wish has the same value as the current deck so it cannot be
      // fulfilled.
      var wish = CardFace.five;
      expect(cards.any((element) => element.face == wish), true);
      var deck = DeckState(turn, wish);

      expect(canPlayWish(deck, cards), false);
    });
    test('canPlayTest', () {
      // We have two kings on our hand so wish can be fulfilled.
      var wish = CardFace.king;
      expect(cards.any((element) => element.face == wish), true);
      var deck = DeckState(turn, wish);

      expect(canPlayWish(deck, cards), true);
    });
    test('canPlayWithPhoenixTest', () {
      // The wish can be fulfilled by using the phoenix to form a pair.
      var wish = CardFace.seven;
      expect(cards.any((element) => element.face == wish), true);
      var deck = DeckState(turn, wish);

      expect(canPlayWish(deck, cards), true);
    });
  });
  group('canPlayWishOnTriplet', () {
    List<Card> cards;
    TichuTurn turn;
    setUp(() {
      cards = [
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
      turn = TichuTurn(TurnType.triplet, [
        Card(CardFace.seven, Color.red),
        Card(CardFace.seven, Color.black),
        Card(CardFace.seven, Color.green)
      ]);
    });
    test('cannotPlayTest', () {
      // We have only one nine and cannot fulfill wish.
      var wish = CardFace.nine;
      var deck = DeckState(turn, wish);
      expect(cards.any((element) => element.face == wish), true);

      expect(canPlayWish(deck, cards), false);
    });
    test('canPlayTest', () {
      // We have three kings on the hand and can fulfill wish.
      var wish = CardFace.king;
      var deck = DeckState(turn, wish);
      expect(cards.any((element) => element.face == wish), true);

      expect(canPlayWish(deck, cards), true);
    });
    test('canPlayWithPhoenixTest', () {
      // We have two jacks and the phoenix on the hand and can fulfill wish.
      var wish = CardFace.jack;
      var deck = DeckState(turn, wish);
      expect(cards.any((element) => element.face == wish), true);

      expect(canPlayWish(deck, cards), true);
    });
  });
  group('canPlayWishOnStraight', () {
    var cards = <Card>[
      Card(CardFace.five, Color.green),
      Card(CardFace.phoenix, Color.special),
      Card(CardFace.seven, Color.red),
      Card(CardFace.eight, Color.green),
      Card(CardFace.nine, Color.red),
      Card(CardFace.queen, Color.red)
    ];
    var turn = TichuTurn(TurnType.straight, [
      Card(CardFace.mahJong, Color.special),
      Card(CardFace.two, Color.blue),
      Card(CardFace.three, Color.blue),
      Card(CardFace.four, Color.black),
      Card(CardFace.five, Color.red)
    ]);
    test('canPlayTest', () {
      var wish = CardFace.eight;
      var deck = DeckState(turn, wish);
      expect(canPlayWish(deck, cards), true);
    });
    test('cannotPlayTest', () {
      var wish = CardFace.queen;
      var deck = DeckState(turn, wish);
      expect(canPlayWish(deck, cards), false);
    });
  });
  group('canPlayWishOnPairStraight', () {
    var turn = TichuTurn(TurnType.pairStraight, [
      Card(CardFace.five, Color.red),
      Card(CardFace.five, Color.black),
      Card(CardFace.six, Color.black),
      Card(CardFace.six, Color.green)
    ]);
    test('cannotPlayTest', () {
      var wish = CardFace.eight;
      var cards = <Card>[
        Card(CardFace.eight, Color.red),
        Card(CardFace.eight, Color.black),
        Card(CardFace.nine, Color.red),
        Card(CardFace.phoenix, Color.special)
      ];

      var deck = DeckState(turn, wish);
      expect(cards.any((card) => card.face == wish), true);

      expect(canPlayWish(deck, cards), true);
    });
  });
  group('canPlayWishOnFullHouse', () {
    TichuTurn turn;
    setUp(() {
      turn = TichuTurn(TurnType.fullHouse, [
        Card(CardFace.seven, Color.red),
        Card(CardFace.seven, Color.black),
        Card(CardFace.seven, Color.green),
        Card(CardFace.five, Color.green),
        Card(CardFace.five, Color.red)
      ]);
    });
    test('cannotPlayTripletAndPhoenix', () {
      var wish = CardFace.nine;
      var cards = <Card>[
        Card(CardFace.nine, Color.red),
        Card(CardFace.nine, Color.black),
        Card(CardFace.nine, Color.green),
        Card(CardFace.phoenix, Color.special)
      ];
      var deck = DeckState(turn, wish);
      expect(cards.any((card) => card.face == wish), true);

      expect(canPlayWish(deck, cards), false);
    });
    test('canPlayTripletSingleAndPhoenix', () {
      var wish = CardFace.nine;
      var cards = <Card>[
        Card(CardFace.eight, Color.red),
        Card(CardFace.eight, Color.black),
        Card(CardFace.eight, Color.green),
        Card(CardFace.nine, Color.green),
        Card(CardFace.jack, Color.green),
        Card(CardFace.phoenix, Color.special)
      ];
      var deck = DeckState(turn, wish);
      expect(cards.any((element) => element.face == wish), true);

      expect(canPlayWish(deck, cards), true);
    });
    test('canPlayTwoPairsAndPhoenix', () {
      var wish = CardFace.nine;
      var cards = <Card>[
        Card(CardFace.nine, Color.green),
        Card(CardFace.nine, Color.black),
        Card(CardFace.jack, Color.green),
        Card(CardFace.jack, Color.black),
        Card(CardFace.phoenix, Color.special)
      ];
      var deck = DeckState(turn, wish);
      expect(cards.any((element) => element.face == wish), true);

      expect(canPlayWish(deck, cards), true);
    });
    test('canPlayWithoutPhoenix', () {
      var wish = CardFace.nine;
      var cards = <Card>[
        Card(CardFace.nine, Color.green),
        Card(CardFace.nine, Color.black),
        Card(CardFace.nine, Color.red),
        Card(CardFace.jack, Color.green),
        Card(CardFace.jack, Color.black),
        Card(CardFace.six, Color.red)
      ];
      var deck = DeckState(turn, wish);
      expect(cards.any((element) => element.face == wish), true);

      expect(canPlayWish(deck, cards), true);
    });
    test('cannotPlayWithoutPhoenix', () {
      var wish = CardFace.nine;
      var cards = <Card>[
        Card(CardFace.nine, Color.green),
        Card(CardFace.nine, Color.black),
        Card(CardFace.jack, Color.green),
        Card(CardFace.jack, Color.black),
        Card(CardFace.six, Color.red)
      ];
      var deck = DeckState(turn, wish);
      expect(cards.any((element) => element.face == wish), true);

      expect(canPlayWish(deck, cards), false);
    });
  });
}
