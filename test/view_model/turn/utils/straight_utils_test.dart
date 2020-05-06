import 'package:test/test.dart';
import "package:tichu/view_model/turn/utils/straight_utils.dart";
import 'package:tichu/view_model/turn/tichu_data.dart';

void main() {
  group('removeDuplicates', () {
    List<Card> uniqueCards;
    setUp(() {
      uniqueCards = [
        Card(CardFace.THREE, Color.GREEN),
        Card(CardFace.FOUR, Color.RED),
        Card(CardFace.FIVE, Color.RED),
        Card(CardFace.SIX, Color.RED)
      ];
      uniqueCards.sort(compareCards);
    });
    test('noDuplicateTest', () {
      expect(removeDuplicates(uniqueCards), uniqueCards);
    });
    test('twoDuplicatesTest', () {
      List<Card> duplicateCards = List<Card>.from(uniqueCards);
      duplicateCards.add(Card(CardFace.FIVE, Color.BLACK));
      duplicateCards.add(Card(CardFace.SIX, Color.BLACK));
      duplicateCards.sort(compareCards);

      expect(removeDuplicates(duplicateCards), uniqueCards);
    });
    test('threeDuplicatesTest', () {
      List<Card> duplicateCards = List<Card>.from(uniqueCards);
      duplicateCards.add(Card(CardFace.FIVE, Color.BLACK));
      duplicateCards.add(Card(CardFace.FIVE, Color.RED));
      duplicateCards.sort(compareCards);

      expect(removeDuplicates(duplicateCards), uniqueCards);
    });
  });
  group('getStraights', () {
    final List<Card> sixStraight = [
      Card(CardFace.THREE, Color.GREEN),
      Card(CardFace.FOUR, Color.RED),
      Card(CardFace.FIVE, Color.RED),
      Card(CardFace.SIX, Color.RED),
      Card(CardFace.SEVEN, Color.RED),
      Card(CardFace.EIGHT, Color.RED),
    ];
    test('simpleSixStraightTest', () {
      final int desiredLength = 6;
      List<TichuTurn> straightTurns = getStraights(sixStraight, desiredLength);

      expect(straightTurns.length, 1);
      expect(straightTurns.every((turn) => isStraight(turn.cards)), true);
      expect(straightTurns.every((turn) => turn.cards.length == desiredLength),
          true);
      expect(straightTurns[0].value, 8);
    });
    test('hiddenSixStraightTest', () {
      // Here, we also have duplicates and other cards at hand.
      List<Card> hiddenSixStraight = List<Card>.from(sixStraight);
      hiddenSixStraight.add(Card(CardFace.KING, Color.RED));
      hiddenSixStraight.add(Card(CardFace.QUEEN, Color.RED));
      hiddenSixStraight.add(Card(CardFace.FOUR, Color.RED));
      hiddenSixStraight.add(Card(CardFace.MAH_JONG, Color.SPECIAL));

      final int desiredLength = 5;
      List<TichuTurn> straightTurns =
          getStraights(hiddenSixStraight, desiredLength);

      expect(straightTurns.length, 2);
      expect(straightTurns.every((turn) => isStraight(turn.cards)), true);
      expect(straightTurns.every((turn) => turn.cards.length == desiredLength),
          true);
      expect(straightTurns[0].value, 8);
      expect(straightTurns[1].value, 7);
    });
    test('phoenixAsGapTest', () {
      final List<Card> phoenixStraight = [
        Card(CardFace.THREE, Color.GREEN),
        Card(CardFace.FOUR, Color.RED),
        Card(CardFace.PHOENIX, Color.SPECIAL),
        Card(CardFace.SIX, Color.RED),
        Card(CardFace.SEVEN, Color.RED),
        Card(CardFace.EIGHT, Color.RED),
      ];

      final int desiredLength = 5;
      List<TichuTurn> turns = getStraights(phoenixStraight, desiredLength);

      expect(turns.length, 2);
      expect(turns.every((turn) => isStraight(turn.cards)), true);
      expect(turns.every((turn) => turn.cards.length == desiredLength), true);
      expect(turns[0].value, Card.getValue(CardFace.EIGHT));
      expect(turns[1].value, Card.getValue(CardFace.SEVEN));
    });
    test('phoenixTooSmallTest', () {
      final List<Card> phoenixStraight = [
        Card(CardFace.THREE, Color.GREEN),
        Card(CardFace.FOUR, Color.RED),
        Card(CardFace.PHOENIX, Color.SPECIAL),
        Card(CardFace.SIX, Color.RED),
        Card(CardFace.ACE, Color.RED),
      ];

      final int desiredLength = 5;
      List<TichuTurn> turns = getStraights(phoenixStraight, desiredLength);

      expect(turns.length, 0);
    });
    test('phoenixAsGapAndPromotingTest', () {
      // The cards combine a segment of length four that is promoted to
      // straight.
      final List<Card> phoenixStraight = [
        Card(CardFace.THREE, Color.GREEN),
        Card(CardFace.FOUR, Color.RED),
        Card(CardFace.PHOENIX, Color.SPECIAL),
        Card(CardFace.SIX, Color.RED),
        Card(CardFace.SEVEN, Color.RED),
        Card(CardFace.TEN, Color.GREEN),
        Card(CardFace.JACK, Color.GREEN),
        Card(CardFace.QUEEN, Color.GREEN),
        Card(CardFace.KING, Color.GREEN),
      ];

      final int desiredLength = 5;
      List<TichuTurn> turns = getStraights(phoenixStraight, desiredLength);

      expect(turns.length, 2);
      expect(turns.every((turn) => isStraight(turn.cards)), true);
      expect(turns.every((turn) => turn.cards.length == desiredLength), true);
      expect(turns[0].value, Card.getValue(CardFace.ACE));
      expect(turns[1].value, Card.getValue(CardFace.SEVEN));
    });
    test('phoenixAsLowerGapTest', () {
      final List<Card> phoenixStraight = [
        Card(CardFace.PHOENIX, Color.SPECIAL),
        Card(CardFace.JACK, Color.GREEN),
        Card(CardFace.QUEEN, Color.GREEN),
        Card(CardFace.KING, Color.GREEN),
        Card(CardFace.ACE, Color.RED)
      ];

      final int desiredLength = 5;
      List<TichuTurn> turns = getStraights(phoenixStraight, desiredLength);

      expect(turns.length, 1);
      expect(turns.every((turn) => isStraight(turn.cards)), true);
      expect(turns.every((turn) => turn.cards.length == desiredLength), true);
      expect(turns[0].value, Card.getValue(CardFace.ACE));
    });
  });
  group('getStraightPermutations', () {
    final List<Card> sevenStraight = [
      Card(CardFace.TWO, Color.RED),
      Card(CardFace.THREE, Color.GREEN),
      Card(CardFace.FOUR, Color.RED),
      Card(CardFace.FIVE, Color.RED),
      Card(CardFace.SIX, Color.RED),
      Card(CardFace.SEVEN, Color.RED),
      Card(CardFace.EIGHT, Color.RED)
    ];
    test('getPermutationTest', () {
      List<TichuTurn> turns = getStraightPermutations(sevenStraight);

      expect(turns.length, 6);
      expect(turns.every((element) => isStraight(element.cards)), true);
      expect(turns[0].value, 8);
      expect(turns[0].cards.length, 7);
      expect(turns[1].cards.length, 6);
      expect(turns[1].value, 8);
      expect(turns[2].cards.length, 6);
      expect(turns[2].value, 7);
      expect(turns[3].cards.length, 5);
      expect(turns[3].value, 8);
      expect(turns[4].cards.length, 5);
      expect(turns[4].value, 7);
      expect(turns[5].cards.length, 5);
      expect(turns[5].value, 6);
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
        Card.phoenix(Card.getValue(CardFace.SEVEN)),
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
}
