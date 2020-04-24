import 'package:test/test.dart';
import "package:tichu/view_model/tichu/wish_logic.dart";
import 'package:tichu/view_model/tichu/tichu_data.dart';

void main() {
  group('computeNextWish', () {
    test('noPreviousWishTest', () {
      CardSelection selection = CardSelection({Card.NINE: 1}, null, 0);
      expect(computeNextWish(null, selection), null);
    });
  });

  group('canPlayWishOnSingle', () {
    Map<Card, int> cards;
    TichuTurn turn;
    setUp(() {
      turn = TichuTurn(TurnType.SINGLE, {Card.FIVE: 1});
      cards = {Card.FOUR: 1, Card.PHOENIX: 1, Card.SEVEN: 1, Card.NINE: 1};
    });

    test('cannotPlayTest', () {
      // Make sure that wish card is contained in cards which is assumption of
      // function below.
      Card wish = Card.FOUR;
      expect(cards.containsKey(wish), true);
      DeckState deck = DeckState(turn, wish);

      // The wish is lower than currently played card.
      expect(canPlayWishOnSingle(deck, cards), false);
    });

    test('canPlayTest', () {
      // Make sure that wish card is contained in cards which is assumption of
      // function below.
      Card wish = Card.NINE;
      expect(cards.containsKey(wish), true);
      DeckState deck = DeckState(turn, wish);

      // The wish is higher than deck value and can be played.
      expect(canPlayWishOnSingle(deck, cards), true);
    });
  });

  group('canPlayWishOnPair', () {
    Map<Card, int> cards;
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
      Card wish = Card.KING;
      expect(cards.containsKey(wish), true);
      DeckState deck = DeckState(turn, wish);

      expect(canPlayWishOnPair(deck, cards), true);
    });
    test('canPlayWithPhoenixTest', () {
      // The wish can be fulfilled by using the phoenix to form a pair.
      Card wish = Card.SEVEN;
      expect(cards.containsKey(wish), true);
      DeckState deck = DeckState(turn, wish);

      expect(canPlayWishOnPair(deck, cards), true);
    });
  });

  group('canPlayWishOnTriplet', () {
    Map<Card, int> cards;
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
      Card wish = Card.NINE;
      DeckState deck = DeckState(turn, wish);
      expect(cards.containsKey(wish), true);

      expect(canPlayWishOnTriplet(deck, cards), false);
    });
    test('canPlayTest', () {
      // We have three kings on the hand and can fulfill wish.
      Card wish = Card.KING;
      DeckState deck = DeckState(turn, wish);
      expect(cards.containsKey(wish), true);

      expect(canPlayWishOnTriplet(deck, cards), true);
    });
    test('canPlayWithPhoenixTest', () {
      // We have two jacks and the phoenix on the hand and can fulfill wish.
      Card wish = Card.JACK;
      DeckState deck = DeckState(turn, wish);
      expect(cards.containsKey(wish), true);

      expect(canPlayWishOnTriplet(deck, cards), true);
    });
  });
  group('canPlayWishOnFullHouse', () {
    TichuTurn turn;
    setUp(() {
      turn = TichuTurn(TurnType.FULL_HOUSE, {Card.SEVEN: 3, Card.FIVE: 2});
    });
    test('cannotPlayTripletAndPhoenix', () {
      Card wish = Card.NINE;
      Map<Card, int> cards = {Card.NINE: 3, Card.PHOENIX: 1};
      DeckState deck = DeckState(turn, wish);
      expect(cards.containsKey(wish), true);

      expect(canPlayWishOnFullHouse(deck, cards), false);
    });
    test('canPlayTripletSingleAndPhoenix', () {
      Card wish = Card.NINE;
      Map<Card, int> cards = {
        Card.EIGHT: 3,
        Card.NINE: 1,
        Card.JACK: 1,
        Card.PHOENIX: 1
      };
      DeckState deck = DeckState(turn, wish);
      expect(cards.containsKey(wish), true);

      expect(canPlayWishOnFullHouse(deck, cards), true);
    });
    test('canPlayTwoPairsAndPhoenix', () {
      Card wish = Card.NINE;
      Map<Card, int> cards = {Card.NINE: 2, Card.JACK: 2, Card.PHOENIX: 1};
      DeckState deck = DeckState(turn, wish);
      expect(cards.containsKey(wish), true);

      expect(canPlayWishOnFullHouse(deck, cards), true);
    });
    test('canPlayWithoutPhoenix', () {
      Card wish = Card.NINE;
      Map<Card, int> cards = {Card.NINE: 3, Card.JACK: 2, Card.SIX: 1};
      DeckState deck = DeckState(turn, wish);
      expect(cards.containsKey(wish), true);

      expect(canPlayWishOnFullHouse(deck, cards), true);
    });
    test('cannotPlayWithoutPhoenix', () {
      Card wish = Card.NINE;
      Map<Card, int> cards = {Card.NINE: 2, Card.JACK: 2, Card.SIX: 1};
      DeckState deck = DeckState(turn, wish);
      expect(cards.containsKey(wish), true);

      expect(canPlayWishOnFullHouse(deck, cards), false);
    });
  });
}
