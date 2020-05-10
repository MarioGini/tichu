import 'package:test/test.dart';
import 'package:tichu/view_model/turn/utils/straight_utils.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';

void main() {
  group('removeDuplicates', () {
    List<Card> uniqueCards;
    setUp(() {
      uniqueCards = [
        Card(CardFace.three, Color.green),
        Card(CardFace.four, Color.red),
        Card(CardFace.five, Color.red),
        Card(CardFace.six, Color.red)
      ];
      uniqueCards.sort(compareCards);
    });
    test('noDuplicateTest', () {
      expect(removeDuplicates(uniqueCards), uniqueCards);
    });
    test('twoDuplicatesTest', () {
      var duplicateCards = List<Card>.from(uniqueCards);
      duplicateCards.add(Card(CardFace.five, Color.black));
      duplicateCards.add(Card(CardFace.six, Color.black));
      duplicateCards.sort(compareCards);

      expect(removeDuplicates(duplicateCards), uniqueCards);
    });
    test('threeDuplicatesTest', () {
      var duplicateCards = List<Card>.from(uniqueCards);
      duplicateCards.add(Card(CardFace.five, Color.black));
      duplicateCards.add(Card(CardFace.five, Color.red));
      duplicateCards.sort(compareCards);

      expect(removeDuplicates(duplicateCards), uniqueCards);
    });
  });
  group('getStraights', () {
    final sixStraight = [
      Card(CardFace.three, Color.green),
      Card(CardFace.four, Color.red),
      Card(CardFace.five, Color.red),
      Card(CardFace.six, Color.red),
      Card(CardFace.seven, Color.red),
      Card(CardFace.eight, Color.red),
    ];
    test('simpleSixStraightTest', () {
      final desiredLength = 6;
      var straightTurns = getStraights(sixStraight, desiredLength);

      expect(straightTurns.length, 1);
      expect(straightTurns.every((turn) => isStraight(turn.cards)), true);
      expect(straightTurns.every((turn) => turn.cards.length == desiredLength),
          true);
      expect(straightTurns[0].value, 8);
    });
    test('hiddenSixStraightTest', () {
      // Here, we also have duplicates and other cards at hand.
      var hiddenSixStraight = List<Card>.from(sixStraight);
      hiddenSixStraight.add(Card(CardFace.king, Color.red));
      hiddenSixStraight.add(Card(CardFace.queen, Color.red));
      hiddenSixStraight.add(Card(CardFace.four, Color.red));
      hiddenSixStraight.add(Card(CardFace.mahJong, Color.special));

      final desiredLength = 5;
      var straightTurns = getStraights(hiddenSixStraight, desiredLength);

      expect(straightTurns.length, 2);
      expect(straightTurns.every((turn) => isStraight(turn.cards)), true);
      expect(straightTurns.every((turn) => turn.cards.length == desiredLength),
          true);
      expect(straightTurns[0].value, 8);
      expect(straightTurns[1].value, 7);
    });
    test('phoenixAsGapTest', () {
      final phoenixStraight = [
        Card(CardFace.three, Color.green),
        Card(CardFace.four, Color.red),
        Card(CardFace.phoenix, Color.special),
        Card(CardFace.six, Color.red),
        Card(CardFace.seven, Color.red),
        Card(CardFace.eight, Color.red),
      ];

      final desiredLength = 5;
      var turns = getStraights(phoenixStraight, desiredLength);

      expect(turns.length, 2);
      expect(turns.every((turn) => isStraight(turn.cards)), true);
      expect(turns.every((turn) => turn.cards.length == desiredLength), true);
      expect(turns[0].value, Card.getValue(CardFace.eight));
      expect(turns[1].value, Card.getValue(CardFace.seven));
    });
    test('phoenixTooSmallTest', () {
      final phoenixStraight = [
        Card(CardFace.three, Color.green),
        Card(CardFace.four, Color.red),
        Card(CardFace.phoenix, Color.special),
        Card(CardFace.six, Color.red),
        Card(CardFace.ace, Color.red),
      ];

      final desiredLength = 5;
      var turns = getStraights(phoenixStraight, desiredLength);

      expect(turns.length, 0);
    });
    test('phoenixAsGapAndPromotingTest', () {
      // The cards combine a segment of length four that is promoted to
      // straight.
      final phoenixStraight = [
        Card(CardFace.three, Color.green),
        Card(CardFace.four, Color.red),
        Card(CardFace.phoenix, Color.special),
        Card(CardFace.six, Color.red),
        Card(CardFace.seven, Color.red),
        Card(CardFace.ten, Color.green),
        Card(CardFace.jack, Color.green),
        Card(CardFace.queen, Color.green),
        Card(CardFace.king, Color.green),
      ];

      final desiredLength = 5;
      var turns = getStraights(phoenixStraight, desiredLength);

      expect(turns.length, 2);
      expect(turns.every((turn) => isStraight(turn.cards)), true);
      expect(turns.every((turn) => turn.cards.length == desiredLength), true);
      expect(turns[0].value, Card.getValue(CardFace.ace));
      expect(turns[1].value, Card.getValue(CardFace.seven));
    });
    test('phoenixAsLowerGapTest', () {
      final phoenixStraight = [
        Card(CardFace.phoenix, Color.special),
        Card(CardFace.jack, Color.green),
        Card(CardFace.queen, Color.green),
        Card(CardFace.king, Color.green),
        Card(CardFace.ace, Color.red)
      ];

      final desiredLength = 5;
      var turns = getStraights(phoenixStraight, desiredLength);

      expect(turns.length, 1);
      expect(turns.every((turn) => isStraight(turn.cards)), true);
      expect(turns.every((turn) => turn.cards.length == desiredLength), true);
      expect(turns[0].value, Card.getValue(CardFace.ace));
    });
  });
  group('getStraightPermutations', () {
    final sevenStraight = [
      Card(CardFace.two, Color.red),
      Card(CardFace.three, Color.green),
      Card(CardFace.four, Color.red),
      Card(CardFace.five, Color.red),
      Card(CardFace.six, Color.red),
      Card(CardFace.seven, Color.red),
      Card(CardFace.eight, Color.red)
    ];
    test('getPermutationTest', () {
      var turns = getStraightPermutations(sevenStraight);

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
      var cards = <Card>[
        Card(CardFace.five, Color.black),
        Card(CardFace.four, Color.green),
        Card(CardFace.three, Color.blue),
        Card(CardFace.two, Color.blue),
        Card(CardFace.mahJong, Color.special)
      ];

      expect(isStraight(cards), true);
    });
    test('sevenPhoenixStraightTest', () {
      var cards = <Card>[
        Card(CardFace.five, Color.black),
        Card(CardFace.six, Color.black),
        Card.phoenix(Card.getValue(CardFace.seven)),
        Card(CardFace.four, Color.green),
        Card(CardFace.three, Color.blue),
        Card(CardFace.two, Color.blue)
      ];

      expect(isStraight(cards), true);
    });
    test('straightDragonTest', () {
      var cards = <Card>[
        Card(CardFace.jack, Color.black),
        Card(CardFace.queen, Color.black),
        Card(CardFace.king, Color.green),
        Card(CardFace.ace, Color.blue),
        Card(CardFace.dragon, Color.special)
      ];

      expect(isStraight(cards), false);
    });
  });
}
