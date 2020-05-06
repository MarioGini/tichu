import 'package:test/test.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';
import "package:tichu/view_model/turn/wish_logic.dart";

void main() {
  group('computeNextWish', () {
    CardFace previousWish = CardFace.TEN;
    test('noInputWishTest', () {
      TichuTurn currentTurn =
          TichuTurn(TurnType.SINGLE, [Card(CardFace.EIGHT, Color.BLUE)]);
      CardFace inputWish;

      expect(
          computeNextWish(previousWish, currentTurn, inputWish), previousWish);
    });
    test('inputWishFulfilledTest', () {
      TichuTurn currentTurn =
          TichuTurn(TurnType.SINGLE, [Card(CardFace.TEN, Color.BLUE)]);
      CardFace inputWish;

      expect(computeNextWish(previousWish, currentTurn, inputWish), null);
    });
    test('newInputWishTest', () {
      previousWish = null;
      TichuTurn currentTurn =
          TichuTurn(TurnType.SINGLE, [Card(CardFace.TEN, Color.BLUE)]);
      CardFace inputWish = CardFace.KING;

      expect(computeNextWish(previousWish, currentTurn, inputWish), inputWish);
    });
  });
  group('haveValidWishBomb', () {
    final List<Card> cards = [
      Card(CardFace.EIGHT, Color.BLACK),
      Card(CardFace.EIGHT, Color.GREEN),
      Card(CardFace.EIGHT, Color.RED),
      Card(CardFace.EIGHT, Color.BLUE)
    ];
    test('quartetWishBombTest', () {
      CardFace wish = CardFace.EIGHT;
      TichuTurn turn =
          TichuTurn(TurnType.SINGLE, [Card(CardFace.TEN, Color.BLUE)]);
      DeckState deck = DeckState(turn, wish);

      expect(haveValidWishBomb(deck, cards), true);
    });
    test('noWishBombTest', () {
      CardFace wish = CardFace.EIGHT;
      TichuTurn turn = TichuTurn(TurnType.BOMB, [
        Card(CardFace.NINE, Color.BLACK),
        Card(CardFace.NINE, Color.GREEN),
        Card(CardFace.NINE, Color.RED),
        Card(CardFace.NINE, Color.BLUE)
      ]);
      DeckState deck = DeckState(turn, wish);

      expect(haveValidWishBomb(deck, cards), false);
    });
  });
  group('mahJong', () {
    TichuTurn deckTurn =
        TichuTurn(TurnType.SINGLE, [Card(CardFace.EIGHT, Color.BLACK)]);
    test('noWishPresentTest', () {
      DeckState deck = DeckState(deckTurn, null);
      TichuTurn selectedTurn =
          TichuTurn(TurnType.SINGLE, [Card(CardFace.KING, Color.BLACK)]);
      List<Card> cards = [
        Card(CardFace.FOUR, Color.GREEN),
        Card(CardFace.PHOENIX, Color.SPECIAL),
        Card(CardFace.SEVEN, Color.RED),
        Card(CardFace.NINE, Color.BLACK)
      ];

      expect(mahJong(deck, selectedTurn, cards), false);
    });
    test('wishCardNotAvailableTest', () {
      DeckState deck = DeckState(deckTurn, CardFace.ACE);
      TichuTurn selectedTurn =
          TichuTurn(TurnType.SINGLE, [Card(CardFace.KING, Color.BLACK)]);
      List<Card> cards = [
        Card(CardFace.FOUR, Color.GREEN),
        Card(CardFace.PHOENIX, Color.SPECIAL),
        Card(CardFace.SEVEN, Color.RED),
        Card(CardFace.NINE, Color.BLACK)
      ];

      expect(mahJong(deck, selectedTurn, cards), false);
    });
    test('wishCardNotAvailableTest', () {
      DeckState deck = DeckState(deckTurn, CardFace.ACE);
      TichuTurn selectedTurn =
          TichuTurn(TurnType.SINGLE, [Card(CardFace.ACE, Color.BLACK)]);
      List<Card> cards = [
        Card(CardFace.ACE, Color.BLACK),
        Card(CardFace.FOUR, Color.GREEN),
        Card(CardFace.PHOENIX, Color.SPECIAL),
        Card(CardFace.SEVEN, Color.RED),
        Card(CardFace.NINE, Color.BLACK)
      ];

      expect(mahJong(deck, selectedTurn, cards), false);
    });
    test('couldPlayWishTest', () {
      DeckState deck = DeckState(deckTurn, CardFace.ACE);
      TichuTurn selectedTurn =
          TichuTurn(TurnType.SINGLE, [Card(CardFace.NINE, Color.BLACK)]);
      List<Card> cards = [
        Card(CardFace.ACE, Color.BLACK),
        Card(CardFace.FOUR, Color.GREEN),
        Card(CardFace.PHOENIX, Color.SPECIAL),
        Card(CardFace.SEVEN, Color.RED),
        Card(CardFace.NINE, Color.BLACK)
      ];

      expect(mahJong(deck, selectedTurn, cards), true);
    });
  });
  group('canPlayWishOnSingle', () {
    List<Card> cards;
    TichuTurn turn;
    setUp(() {
      turn = TichuTurn(TurnType.SINGLE, [Card(CardFace.FIVE, Color.BLACK)]);
      cards = [
        Card(CardFace.FOUR, Color.GREEN),
        Card(CardFace.PHOENIX, Color.SPECIAL),
        Card(CardFace.SEVEN, Color.RED),
        Card(CardFace.NINE, Color.BLACK)
      ];
    });
    test('cannotPlayTest', () {
      // Make sure that wish card is contained in cards which is assumption of
      // function below.
      CardFace wish = CardFace.FOUR;
      expect(cards.any((element) => element.face == wish), true);
      DeckState deck = DeckState(turn, wish);

      // The wish is lower than currently played card.
      expect(canPlayWishOnSingle(deck, cards), false);
    });
    test('canPlayTest', () {
      // Make sure that wish card is contained in cards which is assumption of
      // function below.
      CardFace wish = CardFace.NINE;
      expect(cards.any((element) => element.face == wish), true);
      DeckState deck = DeckState(turn, wish);

      // The wish is higher than deck value and can be played.
      expect(canPlayWishOnSingle(deck, cards), true);
    });
  });
  group('canPlayWishOnPair', () {
    List<Card> cards;
    TichuTurn turn;
    setUp(() {
      cards = [
        Card(CardFace.FIVE, Color.GREEN),
        Card(CardFace.SEVEN, Color.RED),
        Card(CardFace.PHOENIX, Color.SPECIAL),
        Card(CardFace.KING, Color.BLACK),
        Card(CardFace.KING, Color.GREEN)
      ];
      turn = TichuTurn(TurnType.PAIR,
          [Card(CardFace.FIVE, Color.RED), Card(CardFace.FIVE, Color.BLACK)]);
    });
    test('cannotPlayTest', () {
      // The wish has the same value as the current deck so it cannot be
      // fulfilled.
      CardFace wish = CardFace.FIVE;
      expect(cards.any((element) => element.face == wish), true);
      DeckState deck = DeckState(turn, wish);

      expect(canPlayWishOnPair(deck, cards), false);
    });
    test('canPlayTest', () {
      // We have two kings on our hand so wish can be fulfilled.
      CardFace wish = CardFace.KING;
      expect(cards.any((element) => element.face == wish), true);
      DeckState deck = DeckState(turn, wish);

      expect(canPlayWishOnPair(deck, cards), true);
    });
    test('canPlayWithPhoenixTest', () {
      // The wish can be fulfilled by using the phoenix to form a pair.
      CardFace wish = CardFace.SEVEN;
      expect(cards.any((element) => element.face == wish), true);
      DeckState deck = DeckState(turn, wish);

      expect(canPlayWishOnPair(deck, cards), true);
    });
  });
  group('canPlayWishOnTriplet', () {
    List<Card> cards;
    TichuTurn turn;
    setUp(() {
      cards = [
        Card(CardFace.FIVE, Color.GREEN),
        Card(CardFace.SEVEN, Color.RED),
        Card(CardFace.NINE, Color.RED),
        Card(CardFace.JACK, Color.RED),
        Card(CardFace.JACK, Color.GREEN),
        Card(CardFace.PHOENIX, Color.SPECIAL),
        Card(CardFace.KING, Color.BLACK),
        Card(CardFace.KING, Color.GREEN),
        Card(CardFace.KING, Color.RED)
      ];
      turn = TichuTurn(TurnType.TRIPLET, [
        Card(CardFace.SEVEN, Color.RED),
        Card(CardFace.SEVEN, Color.BLACK),
        Card(CardFace.SEVEN, Color.GREEN)
      ]);
    });
    test('cannotPlayTest', () {
      // We have only one nine and cannot fulfill wish.
      CardFace wish = CardFace.NINE;
      DeckState deck = DeckState(turn, wish);
      expect(cards.any((element) => element.face == wish), true);

      expect(canPlayWishOnTriplet(deck, cards), false);
    });
    test('canPlayTest', () {
      // We have three kings on the hand and can fulfill wish.
      CardFace wish = CardFace.KING;
      DeckState deck = DeckState(turn, wish);
      expect(cards.any((element) => element.face == wish), true);

      expect(canPlayWishOnTriplet(deck, cards), true);
    });
    test('canPlayWithPhoenixTest', () {
      // We have two jacks and the phoenix on the hand and can fulfill wish.
      CardFace wish = CardFace.JACK;
      DeckState deck = DeckState(turn, wish);
      expect(cards.any((element) => element.face == wish), true);

      expect(canPlayWishOnTriplet(deck, cards), true);
    });
  });
  group('canPlayWishOnStraight', () {
    List<Card> cards = [
      Card(CardFace.FIVE, Color.GREEN),
      Card(CardFace.PHOENIX, Color.SPECIAL),
      Card(CardFace.SEVEN, Color.RED),
      Card(CardFace.EIGHT, Color.GREEN),
      Card(CardFace.NINE, Color.RED),
      Card(CardFace.QUEEN, Color.RED)
    ];
    TichuTurn turn = TichuTurn(TurnType.STRAIGHT, [
      Card(CardFace.MAH_JONG, Color.SPECIAL),
      Card(CardFace.TWO, Color.BLUE),
      Card(CardFace.THREE, Color.BLUE),
      Card(CardFace.FOUR, Color.BLACK),
      Card(CardFace.FIVE, Color.RED)
    ]);
    test('canPlayTest', () {
      CardFace wish = CardFace.EIGHT;
      DeckState deck = DeckState(turn, wish);
      expect(canPlayWish(deck, cards), true);
    });
    test('cannotPlayTest', () {
      CardFace wish = CardFace.QUEEN;
      DeckState deck = DeckState(turn, wish);
      expect(canPlayWish(deck, cards), false);
    });
  });
  // group('canPlayWishOnFullHouse', () {
  //   TichuTurn turn;
  //   setUp(() {
  //     turn = TichuTurn(TurnType.FULL_HOUSE, [
  //       Card(CardFace.SEVEN, Color.RED),
  //       Card(CardFace.SEVEN, Color.BLACK),
  //       Card(CardFace.SEVEN, Color.GREEN),
  //       Card(CardFace.FIVE, Color.GREEN),
  //       Card(CardFace.FIVE, Color.RED)
  //     ]);
  //   });
  //   test('cannotPlayTripletAndPhoenix', () {
  //     CardFace wish = CardFace.NINE;
  //     List<Card> cards = [
  //       Card(CardFace.NINE, Color.RED),
  //       Card(CardFace.NINE, Color.BLACK),
  //       Card(CardFace.NINE, Color.GREEN),
  //       Card(CardFace.PHOENIX, Color.SPECIAL)
  //     ];
  //     DeckState deck = DeckState(turn, wish);
  //     expect(cards.any((element) => element.face == wish), true);

  //     expect(canPlayWishOnFullHouse(deck, cards), false);
  //   });
  //   test('canPlayTripletSingleAndPhoenix', () {
  //     CardFace wish = CardFace.NINE;
  //     List<Card> cards = [
  //       Card(CardFace.EIGHT, Color.RED),
  //       Card(CardFace.EIGHT, Color.BLACK),
  //       Card(CardFace.EIGHT, Color.GREEN),
  //       Card(CardFace.NINE, Color.GREEN),
  //       Card(CardFace.JACK, Color.GREEN),
  //       Card(CardFace.PHOENIX, Color.SPECIAL)
  //     ];
  //     DeckState deck = DeckState(turn, wish);
  //     expect(cards.any((element) => element.face == wish), true);

  //     expect(canPlayWishOnFullHouse(deck, cards), true);
  //   });
  //   test('canPlayTwoPairsAndPhoenix', () {
  //     CardFace wish = CardFace.NINE;
  //     List<Card> cards = [
  //       Card(CardFace.NINE, Color.GREEN),
  //       Card(CardFace.NINE, Color.BLACK),
  //       Card(CardFace.JACK, Color.GREEN),
  //       Card(CardFace.JACK, Color.BLACK),
  //       Card(CardFace.PHOENIX, Color.SPECIAL)
  //     ];
  //     DeckState deck = DeckState(turn, wish);
  //     expect(cards.any((element) => element.face == wish), true);

  //     expect(canPlayWishOnFullHouse(deck, cards), true);
  //   });
  //   test('canPlayWithoutPhoenix', () {
  //     CardFace wish = CardFace.NINE;
  //     List<Card> cards = [
  //       Card(CardFace.NINE, Color.GREEN),
  //       Card(CardFace.NINE, Color.BLACK),
  //       Card(CardFace.NINE, Color.RED),
  //       Card(CardFace.JACK, Color.GREEN),
  //       Card(CardFace.JACK, Color.BLACK),
  //       Card(CardFace.SIX, Color.RED)
  //     ];
  //     DeckState deck = DeckState(turn, wish);
  //     expect(cards.any((element) => element.face == wish), true);

  //     expect(canPlayWishOnFullHouse(deck, cards), true);
  //   });
  //   test('cannotPlayWithoutPhoenix', () {
  //     CardFace wish = CardFace.NINE;
  //     List<Card> cards = [
  //       Card(CardFace.NINE, Color.GREEN),
  //       Card(CardFace.NINE, Color.BLACK),
  //       Card(CardFace.JACK, Color.GREEN),
  //       Card(CardFace.JACK, Color.BLACK),
  //       Card(CardFace.SIX, Color.RED)
  //     ];
  //     DeckState deck = DeckState(turn, wish);
  //     expect(cards.any((element) => element.face == wish), true);

  //     expect(canPlayWishOnFullHouse(deck, cards), false);
  //   });
  // });
}
