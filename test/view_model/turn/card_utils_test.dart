import 'package:test/test.dart';
import "package:tichu/view_model/turn/card_utils.dart";
import 'package:tichu/view_model/turn/tichu_data.dart';

void main() {
  group('occurrences', () {
    final List<Card> cards = [
      Card(CardFace.NINE, Color.RED),
      Card(CardFace.NINE, Color.GREEN),
      Card(CardFace.NINE, Color.GREEN),
      Card(CardFace.KING, Color.GREEN)
    ];
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
  });
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
    final TichuTurn expectedTurn = TichuTurn(TurnType.STRAIGHT, sixStraight);
    test('simpleSixStraightTest', () {
      List<TichuTurn> straightTurns = getStraights(sixStraight, 6);

      // expect(straightTurns.length, 3);
      // expect(straightTurns.first, expectedTurn);
      // expect(straightTurns[1].value, 8);
      // expect(straightTurns[1].cards.length, 5);
      // expect(straightTurns[2].value, 7);
      // expect(straightTurns[2].cards.length, 5);
    });
    test('hiddenSixStraightTest', () {
      // Here, we also have duplicates and other cards at hand.
      List<Card> hiddenSixStraight = List<Card>.from(sixStraight);
      hiddenSixStraight.add(Card(CardFace.KING, Color.RED));
      hiddenSixStraight.add(Card(CardFace.QUEEN, Color.RED));
      hiddenSixStraight.add(Card(CardFace.FOUR, Color.RED));
      hiddenSixStraight.add(Card(CardFace.MAH_JONG, Color.SPECIAL));

      List<TichuTurn> straightTurns = getStraights(hiddenSixStraight, 6);

      // expect(straightTurns.length, 3);
      // expect(straightTurns.first, expectedTurn);
      // expect(straightTurns[1].value, 8);
      // expect(straightTurns[1].cards.length, 5);
      // expect(straightTurns[2].value, 7);
      // expect(straightTurns[2].cards.length, 5);
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
