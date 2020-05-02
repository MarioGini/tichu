import 'package:test/test.dart';
import "package:tichu/view_model/turn/utils/pair_straight_utils.dart";
import 'package:tichu/view_model/turn/tichu_data.dart';

void main() {
  group('getPairStraights', () {
    test('removeTripleCardsTest', () {
      List<Card> cards = [
        Card(CardFace.THREE, Color.GREEN),
        Card(CardFace.THREE, Color.RED),
        Card(CardFace.THREE, Color.BLACK),
        Card(CardFace.FOUR, Color.RED),
        Card(CardFace.FOUR, Color.BLACK),
        Card(CardFace.FIVE, Color.RED),
        Card(CardFace.SIX, Color.RED),
        Card(CardFace.SEVEN, Color.RED),
        Card(CardFace.EIGHT, Color.RED),
      ];

      List<TichuTurn> turns = getPairStraights(cards, 4);

      expect(turns.length, 1);
      expect(turns.every((element) => isPairStraight(element.cards)), true);
      expect(turns[0].value, 4);
      expect(turns[0].cards.length, 4);
    });
    test('twoSeparatedPairStraightsTest', () {
      List<Card> cards = [
        Card(CardFace.TWO, Color.BLACK),
        Card(CardFace.THREE, Color.GREEN),
        Card(CardFace.THREE, Color.RED),
        Card(CardFace.THREE, Color.BLACK),
        Card(CardFace.FOUR, Color.RED),
        Card(CardFace.FOUR, Color.BLACK),
        Card(CardFace.FIVE, Color.RED),
        Card(CardFace.SIX, Color.RED),
        Card(CardFace.SEVEN, Color.RED),
        Card(CardFace.SEVEN, Color.GREEN),
        Card(CardFace.EIGHT, Color.RED),
        Card(CardFace.EIGHT, Color.BLACK),
        Card(CardFace.NINE, Color.BLACK),
        Card(CardFace.NINE, Color.RED)
      ];
      int desiredLength = 4;
      List<TichuTurn> turns = getPairStraights(cards, desiredLength);

      expect(turns.length, 3);
      expect(turns.every((turn) => isPairStraight(turn.cards)), true);
      expect(turns.every((turn) => turn.cards.length == desiredLength), true);
      expect(turns[0].value, 9);
      expect(turns[1].value, 8);
      expect(turns[2].value, 4);
    });
  });
  group('getPairStraightPermutations', () {
    final List<Card> fourPairStraight = [
      Card(CardFace.TWO, Color.RED),
      Card(CardFace.TWO, Color.GREEN),
      Card(CardFace.THREE, Color.RED),
      Card(CardFace.THREE, Color.BLACK),
      Card(CardFace.FOUR, Color.RED),
      Card(CardFace.FOUR, Color.BLACK),
      Card(CardFace.FIVE, Color.RED),
      Card(CardFace.FIVE, Color.GREEN)
    ];
    test('standardTest', () {
      List<TichuTurn> turns = getPairStraightPermutations(fourPairStraight);

      expect(turns.length, 6);
      expect(turns.every((element) => isPairStraight(element.cards)), true);
      expect(turns[0].value, 5);
      expect(turns[0].cards.length, 8);
      expect(turns[1].value, 5);
      expect(turns[1].cards.length, 6);
      expect(turns[2].value, 4);
      expect(turns[2].cards.length, 6);
      expect(turns[3].value, 5);
      expect(turns[3].cards.length, 4);
      expect(turns[4].value, 4);
      expect(turns[4].cards.length, 4);
      expect(turns[5].value, 3);
      expect(turns[5].cards.length, 4);
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
}
