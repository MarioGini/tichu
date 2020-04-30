import 'package:test/test.dart';
import "package:tichu/view_model/turn/card_utils.dart";
import 'package:tichu/view_model/turn/tichu_data.dart';

void main() {
  group('occurrences', () {
    List<Card> cards;
    setUp(() {
      cards = [
        Card(CardFace.NINE, Color.RED),
        Card(CardFace.NINE, Color.GREEN),
        Card(CardFace.NINE, Color.GREEN),
        Card(CardFace.KING, Color.GREEN)
      ];
    });
    test('threeOccurrencesTest', () {
      expect(occurrences(CardFace.NINE, cards), 3);
    });
    test('singleOccurrenceTest', () {
      expect(occurrences(CardFace.KING, cards), 1);
    });
    test('noOccurrencesTest', () {
      expect(occurrences(CardFace.TWO, cards), 0);
    });
  });
  group('getHighestStraight', () {
    test('simpleSixStraight', () {
      List<Card> cards = [
        Card(CardFace.TWO, Color.RED),
        Card(CardFace.THREE, Color.GREEN),
        Card(CardFace.FOUR, Color.RED)
      ];
      TichuTurn expectedTurn = TichuTurn(TurnType.STRAIGHT, cards);
    });
  });
  group('uniformColor', () {
    test('uniformColorTest', () {
      List<Card> cards = [
        Card(CardFace.FIVE, Color.RED),
        Card(CardFace.JACK, Color.RED),
        Card(CardFace.KING, Color.RED)
      ];

      expect(uniformColor(cards), true);
    });
    test('nonUniformColorsTest', () {
      List<Card> cards = [
        Card(CardFace.FIVE, Color.RED),
        Card(CardFace.JACK, Color.RED),
        Card(CardFace.DOG, Color.SPECIAL)
      ];

      expect(uniformColor(cards), false);
    });
  });
  group('isStraight', () {
    test('fiveStraightTest', () {
      List<Card> cards = [
        Card(CardFace.FIVE, Color.BLACK),
        Card(CardFace.FOUR, Color.GREEN),
        Card(CardFace.THREE, Color.BLUE),
        Card(CardFace.TWO, Color.BLUE),
        Card(CardFace.MAH_JONG, Color.SPECIAL)
      ];

      expect(isStraight(cards), true);
    });
    test('sevenPhoenixStraightTest', () {
      List<Card> cards = [
        Card(CardFace.FIVE, Color.BLACK),
        Card(CardFace.SIX, Color.BLACK),
        Card.phoenix(7),
        Card(CardFace.FOUR, Color.GREEN),
        Card(CardFace.THREE, Color.BLUE),
        Card(CardFace.TWO, Color.BLUE)
      ];

      expect(isStraight(cards), true);
    });
    test('straightDragonTest', () {
      List<Card> cards = [
        Card(CardFace.JACK, Color.BLACK),
        Card(CardFace.QUEEN, Color.BLACK),
        Card(CardFace.KING, Color.GREEN),
        Card(CardFace.ACE, Color.BLUE),
        Card(CardFace.DRAGON, Color.SPECIAL)
      ];

      expect(isStraight(cards), false);
    });
  });
  group('isPairStraight', () {
    test('twoPairStraightTest', () {
      List<Card> cards = [
        Card(CardFace.FIVE, Color.BLACK),
        Card(CardFace.FIVE, Color.GREEN),
        Card(CardFace.SIX, Color.BLUE),
        Card(CardFace.SIX, Color.GREEN)
      ];

      expect(isPairStraight(cards), true);
    });
    test('threePairStraightPhoenixTest', () {
      List<Card> cards = [
        Card(CardFace.FIVE, Color.BLACK),
        Card(CardFace.FIVE, Color.GREEN),
        Card(CardFace.SEVEN, Color.RED),
        Card(CardFace.SIX, Color.BLUE),
        Card(CardFace.SIX, Color.GREEN),
        Card.phoenix(7)
      ];

      expect(isPairStraight(cards), true);
    });
    test('pairStraightOddCardsTest', () {
      List<Card> cards = [
        Card(CardFace.FIVE, Color.BLACK),
        Card(CardFace.FIVE, Color.GREEN),
        Card(CardFace.SEVEN, Color.RED),
        Card(CardFace.SIX, Color.BLUE),
        Card(CardFace.SIX, Color.GREEN),
        Card.phoenix(7),
        Card(CardFace.EIGHT, Color.BLACK)
      ];

      expect(isPairStraight(cards), false);
    });
    test('pairStraightDogTest', () {
      List<Card> cards = [
        Card(CardFace.FIVE, Color.BLACK),
        Card(CardFace.FIVE, Color.GREEN),
        Card(CardFace.SEVEN, Color.RED),
        Card(CardFace.SIX, Color.BLUE),
        Card(CardFace.SIX, Color.GREEN),
        Card.phoenix(7),
        Card(CardFace.DOG, Color.SPECIAL)
      ];

      expect(isPairStraight(cards), false);
    });
  });
  group('isFullHouse', () {
    test('standardSituationTest', () {
      List<Card> cards = [
        Card(CardFace.TWO, Color.BLACK),
        Card(CardFace.TWO, Color.GREEN),
        Card(CardFace.TWO, Color.RED),
        Card(CardFace.FIVE, Color.BLACK),
        Card(CardFace.FIVE, Color.GREEN)
      ];

      expect(isFullHouse(cards), true);
    });
    test('phoenixTest', () {
      List<Card> cards = [
        Card.phoenix(5),
        Card(CardFace.TWO, Color.GREEN),
        Card(CardFace.TWO, Color.RED),
        Card(CardFace.FIVE, Color.BLACK),
        Card(CardFace.FIVE, Color.GREEN)
      ];

      expect(isFullHouse(cards), true);
    });
  });
}
