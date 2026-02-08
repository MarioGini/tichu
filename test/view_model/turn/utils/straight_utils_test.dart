import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/view_model/turn/utils/straight_utils.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';

void main() {
  group('removeDuplicates', () {
    List<Card> uniqueCards = [];
    setUp(() {
      uniqueCards = [
        Card(CardFace.three, CardColor.green),
        Card(CardFace.four, CardColor.red),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.six, CardColor.red),
      ];
      uniqueCards.sort(compareCards);
    });
    test('noDuplicateTest', () {
      expect(removeDuplicates(uniqueCards), uniqueCards);
    });
    test('twoDuplicatesTest', () {
      var duplicateCards = List<Card>.from(uniqueCards);
      duplicateCards.add(Card(CardFace.five, CardColor.black));
      duplicateCards.add(Card(CardFace.six, CardColor.black));
      duplicateCards.sort(compareCards);

      expect(removeDuplicates(duplicateCards), uniqueCards);
    });
    test('threeDuplicatesTest', () {
      var duplicateCards = List<Card>.from(uniqueCards);
      duplicateCards.add(Card(CardFace.five, CardColor.black));
      duplicateCards.add(Card(CardFace.five, CardColor.red));
      duplicateCards.sort(compareCards);

      expect(removeDuplicates(duplicateCards), uniqueCards);
    });
  });
  group('getStraights', () {
    final sixStraight = [
      Card(CardFace.three, CardColor.green),
      Card(CardFace.four, CardColor.red),
      Card(CardFace.five, CardColor.red),
      Card(CardFace.six, CardColor.red),
      Card(CardFace.seven, CardColor.red),
      Card(CardFace.eight, CardColor.red),
    ];
    test('simpleSixStraightTest', () {
      final desiredLength = 6;
      var straightTurns = getStraights(sixStraight, desiredLength);

      expect(straightTurns.length, 1);
      expect(straightTurns.every((turn) => isStraight(turn.cards)), true);
      expect(
        straightTurns.every((turn) => turn.cards.length == desiredLength),
        true,
      );
      expect(straightTurns[0].value, 8);
    });
    test('hiddenSixStraightTest', () {
      // Here, we also have duplicates and other cards at hand.
      var hiddenSixStraight = List<Card>.from(sixStraight);
      hiddenSixStraight.add(Card(CardFace.king, CardColor.red));
      hiddenSixStraight.add(Card(CardFace.queen, CardColor.red));
      hiddenSixStraight.add(Card(CardFace.four, CardColor.red));
      hiddenSixStraight.add(Card(CardFace.mahJong, CardColor.special));

      final desiredLength = 5;
      var straightTurns = getStraights(hiddenSixStraight, desiredLength);

      expect(straightTurns.length, 2);
      expect(straightTurns.every((turn) => isStraight(turn.cards)), true);
      expect(
        straightTurns.every((turn) => turn.cards.length == desiredLength),
        true,
      );
      expect(straightTurns[0].value, 8);
      expect(straightTurns[1].value, 7);
    });
    test('phoenixAsGapTest', () {
      final phoenixStraight = [
        Card(CardFace.three, CardColor.green),
        Card(CardFace.four, CardColor.red),
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.six, CardColor.red),
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.eight, CardColor.red),
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
        Card(CardFace.three, CardColor.green),
        Card(CardFace.four, CardColor.red),
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.six, CardColor.red),
        Card(CardFace.ace, CardColor.red),
      ];

      final desiredLength = 5;
      var turns = getStraights(phoenixStraight, desiredLength);

      expect(turns.length, 0);
    });
    test('phoenixAsGapAndPromotingTest', () {
      // The cards combine a segment of length four that is promoted to
      // straight.
      final phoenixStraight = [
        Card(CardFace.three, CardColor.green),
        Card(CardFace.four, CardColor.red),
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.six, CardColor.red),
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.ten, CardColor.green),
        Card(CardFace.jack, CardColor.green),
        Card(CardFace.queen, CardColor.green),
        Card(CardFace.king, CardColor.green),
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
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.jack, CardColor.green),
        Card(CardFace.queen, CardColor.green),
        Card(CardFace.king, CardColor.green),
        Card(CardFace.ace, CardColor.red),
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
      Card(CardFace.two, CardColor.red),
      Card(CardFace.three, CardColor.green),
      Card(CardFace.four, CardColor.red),
      Card(CardFace.five, CardColor.red),
      Card(CardFace.six, CardColor.red),
      Card(CardFace.seven, CardColor.red),
      Card(CardFace.eight, CardColor.red),
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
        Card(CardFace.five, CardColor.black),
        Card(CardFace.four, CardColor.green),
        Card(CardFace.three, CardColor.blue),
        Card(CardFace.two, CardColor.blue),
        Card(CardFace.mahJong, CardColor.special),
      ];

      expect(isStraight(cards), true);
    });
    test('sevenPhoenixStraightTest', () {
      var cards = <Card>[
        Card(CardFace.five, CardColor.black),
        Card(CardFace.six, CardColor.black),
        Card.phoenix(Card.getValue(CardFace.seven)),
        Card(CardFace.four, CardColor.green),
        Card(CardFace.three, CardColor.blue),
        Card(CardFace.two, CardColor.blue),
      ];

      expect(isStraight(cards), true);
    });
    test('straightDragonTest', () {
      var cards = <Card>[
        Card(CardFace.jack, CardColor.black),
        Card(CardFace.queen, CardColor.black),
        Card(CardFace.king, CardColor.green),
        Card(CardFace.ace, CardColor.blue),
        Card(CardFace.dragon, CardColor.special),
      ];

      expect(isStraight(cards), false);
    });
  });
}
