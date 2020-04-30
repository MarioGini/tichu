import 'package:test/test.dart';
import 'package:tichu/view_model/turn/find_turn.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';

void main() {
  group('singles', () {
    test('standardTest', () {
      Card testCard = Card(CardFace.SEVEN, Color.BLACK);
      expect(checkSingle(testCard), TichuTurn(TurnType.SINGLE, [testCard]));
    });
    test('phoenixTest', () {
      Card testCard = Card.phoenix(8.5);
      expect(checkSingle(testCard), TichuTurn(TurnType.SINGLE, [testCard]));
    });
    test('dragonTest', () {
      Card testCard = Card(CardFace.DRAGON, Color.SPECIAL);
      expect(checkSingle(testCard), TichuTurn(TurnType.DRAGON, [testCard]));
    });
    test('dogTest', () {
      Card testCard = Card(CardFace.DOG, Color.SPECIAL);
      expect(checkSingle(testCard), TichuTurn(TurnType.DOG, [testCard]));
    });
  });
  group('pairs', () {
    test('standardTest', () {
      List<Card> cards = [
        Card(CardFace.FIVE, Color.BLUE),
        Card(CardFace.FIVE, Color.RED)
      ];
      expect(checkForPair(cards), TichuTurn(TurnType.PAIR, cards));
    });
    test('phoenixInvalidTest', () {
      List<Card> cards = [Card(CardFace.FIVE, Color.BLUE), Card.phoenix(4)];
      expect(checkForPair(cards), null);
    });
    test('phoenixValidTest', () {
      List<Card> cards = [Card(CardFace.FIVE, Color.BLUE), Card.phoenix(5)];
      expect(checkForPair(cards), TichuTurn(TurnType.PAIR, cards));
    });
  });
  group('triplets', () {
    test('standardTest', () {
      List<Card> cards = [
        Card(CardFace.FIVE, Color.BLUE),
        Card(CardFace.FIVE, Color.RED),
        Card(CardFace.FIVE, Color.BLACK),
      ];
      expect(checkForTriplet(cards), TichuTurn(TurnType.TRIPLET, cards));
    });
    test('phoenixInvalidTest', () {
      List<Card> cards = [
        Card(CardFace.FIVE, Color.BLUE),
        Card(CardFace.FIVE, Color.GREEN),
        Card.phoenix(4.0)
      ];
      expect(checkForTriplet(cards), null);
    });
    test('phoenixValidTest', () {
      List<Card> cards = [
        Card(CardFace.FIVE, Color.BLUE),
        Card(CardFace.FIVE, Color.GREEN),
        Card.phoenix(5.0)
      ];
      expect(checkForTriplet(cards), TichuTurn(TurnType.TRIPLET, cards));
    });
  });
  group('quartets', () {
    test('bombTest', () {
      List<Card> cards = [
        Card(CardFace.FIVE, Color.BLUE),
        Card(CardFace.FIVE, Color.RED),
        Card(CardFace.FIVE, Color.BLACK),
        Card(CardFace.FIVE, Color.GREEN),
      ];
      expect(checkForQuartet(cards), TichuTurn(TurnType.BOMB, cards));
    });
    test('phoenixInvalidBombTest', () {
      List<Card> cards = [
        Card(CardFace.FIVE, Color.BLUE),
        Card(CardFace.FIVE, Color.BLACK),
        Card(CardFace.FIVE, Color.GREEN),
        Card.phoenix(5.0)
      ];
      expect(checkForQuartet(cards), null);
    });
    test('pairStraightTest', () {
      // The list should be sorted.
      List<Card> cards = [
        Card(CardFace.SIX, Color.GREEN),
        Card.phoenix(6.0),
        Card(CardFace.FIVE, Color.BLUE),
        Card(CardFace.FIVE, Color.GREEN)
      ];
      expect(checkForQuartet(cards), TichuTurn(TurnType.PAIR_STRAIGHT, cards));
    });
  });
  group('fiveCards', () {
    test('standardStraightTest', () {
      List<Card> cards = [
        Card(CardFace.FOUR, Color.BLUE),
        Card(CardFace.FIVE, Color.RED),
        Card(CardFace.SEVEN, Color.GREEN),
        Card(CardFace.SIX, Color.BLUE),
        Card(CardFace.EIGHT, Color.GREEN)
      ];
      expect(checkFives(cards), TichuTurn(TurnType.STRAIGHT, cards));
    });
    test('phoenixStraightTest', () {
      List<Card> cards = [
        Card(CardFace.FOUR, Color.BLUE),
        Card(CardFace.FIVE, Color.RED),
        Card.phoenix(7),
        Card(CardFace.SIX, Color.BLUE),
        Card(CardFace.EIGHT, Color.GREEN)
      ];
      expect(checkFives(cards), TichuTurn(TurnType.STRAIGHT, cards));
    });
    test('straightBombTest', () {
      List<Card> cards = [
        Card(CardFace.FOUR, Color.BLUE),
        Card(CardFace.FIVE, Color.BLUE),
        Card(CardFace.SEVEN, Color.BLUE),
        Card(CardFace.SIX, Color.BLUE),
        Card(CardFace.EIGHT, Color.BLUE)
      ];
      expect(checkFives(cards), TichuTurn(TurnType.BOMB, cards));
    });
    test('straightBombTest', () {
      List<Card> cards = [
        Card(CardFace.FOUR, Color.BLACK),
        Card(CardFace.FOUR, Color.BLUE),
        Card(CardFace.FOUR, Color.GREEN),
        Card(CardFace.SIX, Color.BLUE),
        Card.phoenix(6)
      ];
      expect(checkFives(cards), TichuTurn(TurnType.FULL_HOUSE, cards));
    });
  });
  group('checkBigTurns', () {
    test('eightStraightTest', () {
      List<Card> cards = [
        Card(CardFace.FOUR, Color.BLUE),
        Card(CardFace.FIVE, Color.GREEN),
        Card(CardFace.SIX, Color.BLUE),
        Card(CardFace.JACK, Color.BLUE),
        Card(CardFace.SEVEN, Color.BLUE),
        Card(CardFace.EIGHT, Color.BLUE),
        Card(CardFace.NINE, Color.BLUE),
        Card(CardFace.TEN, Color.BLUE)
      ];
      expect(checkBigTurns(cards), TichuTurn(TurnType.STRAIGHT, cards));
    });
    test('fourPairStraightTest', () {
      List<Card> cards = [
        Card(CardFace.FOUR, Color.BLUE),
        Card(CardFace.FOUR, Color.GREEN),
        Card(CardFace.FIVE, Color.BLUE),
        Card(CardFace.SIX, Color.BLUE),
        Card(CardFace.FIVE, Color.BLACK),
        Card(CardFace.SIX, Color.BLACK),
        Card(CardFace.SEVEN, Color.BLUE),
        Card(CardFace.SEVEN, Color.RED)
      ];
      expect(checkBigTurns(cards), TichuTurn(TurnType.PAIR_STRAIGHT, cards));
    });
  });
  group('getTurn', () {
    test('twoPairsTest', () {
      List<Card> cards = [
        Card(CardFace.FOUR, Color.BLUE),
        Card(CardFace.FOUR, Color.GREEN),
        Card(CardFace.FIVE, Color.BLUE),
        Card.phoenix(5)
      ];
      expect(getTurn(cards), TichuTurn(TurnType.PAIR_STRAIGHT, cards));
    });
    test('invalidTripletTest', () {
      List<Card> cards = [
        Card(CardFace.FOUR, Color.BLUE),
        Card(CardFace.FOUR, Color.GREEN),
        Card.phoenix(5)
      ];
      expect(getTurn(cards), null);
    });
  });
}
