import 'package:test/test.dart';
import 'package:tichu/view_model/tichu/find_turn.dart';
import 'package:tichu/view_model/tichu/tichu_data.dart';

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
      expect(checkForTriplet(cards), TichuTurn(TurnType.PAIR, cards));
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
}
