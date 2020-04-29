import 'package:test/test.dart';
import "package:tichu/view_model/tichu/wish_logic.dart";
import 'package:tichu/view_model/tichu/tichu_data.dart';

void main() {
  group('computeNextWish', () {
    test('noPreviousWishTest', () {});
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
      //expect(cards.containsKey(wish), true);
      DeckState deck = DeckState(turn, wish);

      // The wish is lower than currently played card.
      expect(canPlayWishOnSingle(deck, cards), false);
    });

    test('canPlayTest', () {
      // Make sure that wish card is contained in cards which is assumption of
      // function below.
      CardFace wish = CardFace.NINE;
      //expect(cards.containsKey(wish), true);
      DeckState deck = DeckState(turn, wish);

      // The wish is higher than deck value and can be played.
      expect(canPlayWishOnSingle(deck, cards), true);
    });
  });

  group('canPlayWishOnPair', () {
    List<Card> cards;
    TichuTurn turn;
    setUp(() {
      cards = {Card.FIVE: 1, Card.SEVEN: 1, Card.PHOENIX: 1, Card.KING: 2};
      turn = TichuTurn(TurnType.PAIR, {Card.FIVE: 2});
    });
    test('cannotPlayTest', () {
      // The wish has the same value as the current deck so it cannot be
      // fulfilled.
      Card wish = Card.FIVE;
      expect(cards.containsKey(wish), true);
      DeckState deck = DeckState(turn, wish);

      expect(canPlayWishOnPair(deck, cards), false);
    });
    test('canPlayTest', () {
      // We have two kings on our hand so wish can be fulfilled.
      CardFace wish = CardFace.KING;
      //expect(cards.containsKey(wish), true);
      DeckState deck = DeckState(turn, wish);

      expect(canPlayWishOnPair(deck, cards), true);
    });
    test('canPlayWithPhoenixTest', () {
      // The wish can be fulfilled by using the phoenix to form a pair.
      CardFace wish = CardFace.SEVEN;
      //expect(cards.containsKey(wish), true);
      DeckState deck = DeckState(turn, wish);

      expect(canPlayWishOnPair(deck, cards), true);
    });
  });

  group('canPlayWishOnTriplet', () {
    List<Card> cards;
    TichuTurn turn;
    setUp(() {
      cards = {
        Card.FIVE: 1,
        Card.SEVEN: 1,
        Card.NINE: 1,
        Card.JACK: 2,
        Card.PHOENIX: 1,
        Card.KING: 3
      };
      turn = TichuTurn(TurnType.TRIPLET, {Card.SEVEN: 3});
    });
    test('cannotPlayTest', () {
      // We have only one nine and cannot fulfill wish.
      CardFace wish = CardFace.NINE;
      DeckState deck = DeckState(turn, wish);
      //expect(cards.containsKey(wish), true);

      expect(canPlayWishOnTriplet(deck, cards), false);
    });
    test('canPlayTest', () {
      // We have three kings on the hand and can fulfill wish.
      CardFace wish = CardFace.KING;
      DeckState deck = DeckState(turn, wish);
      //expect(cards.containsKey(wish), true);

      expect(canPlayWishOnTriplet(deck, cards), true);
    });
    test('canPlayWithPhoenixTest', () {
      // We have two jacks and the phoenix on the hand and can fulfill wish.
      CardFace wish = CardFace.JACK;
      DeckState deck = DeckState(turn, wish);
      //expect(cards.containsKey(wish), true);

      expect(canPlayWishOnTriplet(deck, cards), true);
    });
  });
  group('canPlayWishOnFullHouse', () {
    TichuTurn turn;
    setUp(() {
      turn = TichuTurn(TurnType.FULL_HOUSE, {Card.SEVEN: 3, Card.FIVE: 2});
    });
    test('cannotPlayTripletAndPhoenix', () {
      CardFace wish = CardFace.NINE;
      List<Card> cards = {Card.NINE: 3, Card.PHOENIX: 1};
      DeckState deck = DeckState(turn, wish);
      // expect(cards.containsKey(wish), true);

      expect(canPlayWishOnFullHouse(deck, cards), false);
    });
    test('canPlayTripletSingleAndPhoenix', () {
      CardFace wish = CardFace.NINE;
      List<Card> cards = {
        Card.EIGHT: 3,
        Card.NINE: 1,
        Card.JACK: 1,
        Card.PHOENIX: 1
      };
      DeckState deck = DeckState(turn, wish);
      //expect(cards.containsKey(wish), true);

      expect(canPlayWishOnFullHouse(deck, cards), true);
    });
    test('canPlayTwoPairsAndPhoenix', () {
      Card wish = Card.NINE;
      List<Card> cards = {Card.NINE: 2, Card.JACK: 2, Card.PHOENIX: 1};
      DeckState deck = DeckState(turn, wish);
      expect(cards.containsKey(wish), true);

      expect(canPlayWishOnFullHouse(deck, cards), true);
    });
    test('canPlayWithoutPhoenix', () {
      CardFace wish = CardFace.NINE;
      List<Card> cards = {Card.NINE: 3, Card.JACK: 2, Card.SIX: 1};
      DeckState deck = DeckState(turn, wish);
      //expect(cards.containsKey(wish), true);

      expect(canPlayWishOnFullHouse(deck, cards), true);
    });
    test('cannotPlayWithoutPhoenix', () {
      CardFace wish = CardFace.NINE;
      List<Card> cards = {Card.NINE: 2, Card.JACK: 2, Card.SIX: 1};
      DeckState deck = DeckState(turn, wish);
      //expect(cards.containsKey(wish), true);

      expect(canPlayWishOnFullHouse(deck, cards), false);
    });
  });
}
