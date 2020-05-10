import 'package:test/test.dart';
import 'package:tichu/view_model/turn/utils/pair_straight_utils.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';

void main() {
  group('getPairStraights', () {
    test('removeTripleCardsTest', () {
      var cards = <Card>[
        Card(CardFace.three, Color.green),
        Card(CardFace.three, Color.red),
        Card(CardFace.three, Color.black),
        Card(CardFace.four, Color.red),
        Card(CardFace.four, Color.black),
        Card(CardFace.five, Color.red),
        Card(CardFace.six, Color.red),
        Card(CardFace.seven, Color.red),
        Card(CardFace.eight, Color.red),
      ];
      var desiredLength = 4;
      var turns = getPairStraights(cards, 4);

      expect(turns.length, 1);
      expect(turns.every((element) => isPairStraight(element.cards)), true);
      expect(turns.every((turn) => turn.cards.length == desiredLength), true);
      expect(turns[0].value, Card.getValue(CardFace.four));
    });
    test('twoSeparatedPairStraightsTest', () {
      var cards = <Card>[
        Card(CardFace.two, Color.black),
        Card(CardFace.three, Color.green),
        Card(CardFace.three, Color.red),
        Card(CardFace.three, Color.black),
        Card(CardFace.four, Color.red),
        Card(CardFace.four, Color.black),
        Card(CardFace.five, Color.red),
        Card(CardFace.six, Color.red),
        Card(CardFace.seven, Color.red),
        Card(CardFace.seven, Color.green),
        Card(CardFace.eight, Color.red),
        Card(CardFace.eight, Color.black),
        Card(CardFace.nine, Color.black),
        Card(CardFace.nine, Color.red)
      ];
      var desiredLength = 4;
      var turns = getPairStraights(cards, desiredLength);

      expect(turns.length, 3);
      expect(turns.every((turn) => isPairStraight(turn.cards)), true);
      expect(turns.every((turn) => turn.cards.length == desiredLength), true);
      expect(turns[0].value, Card.getValue(CardFace.nine));
      expect(turns[1].value, Card.getValue(CardFace.eight));
      expect(turns[2].value, Card.getValue(CardFace.four));
    });
    test('phoenixFusionTest', () {
      var cards = <Card>[
        Card(CardFace.three, Color.green),
        Card(CardFace.three, Color.red),
        Card(CardFace.four, Color.black),
        Card(CardFace.phoenix, Color.special),
        Card(CardFace.five, Color.red),
        Card(CardFace.five, Color.black)
      ];
      var desiredLength = 4;
      var turns = getPairStraights(cards, desiredLength);

      expect(turns.length, 2);
      expect(turns.every((turn) => isPairStraight(turn.cards)), true);
      expect(turns.every((turn) => turn.cards.length == desiredLength), true);
      expect(turns[0].value, Card.getValue(CardFace.five));
      expect(turns[1].value, Card.getValue(CardFace.four));
    });
    test('phoenixPaddingTest', () {
      var cards = <Card>[
        Card(CardFace.two, Color.black),
        Card(CardFace.three, Color.green),
        Card(CardFace.three, Color.red),
        Card(CardFace.four, Color.black),
        Card(CardFace.phoenix, Color.special),
        Card(CardFace.six, Color.red)
      ];
      var desiredLength = 4;
      var turns = getPairStraights(cards, desiredLength);

      expect(turns.length, 2);
      expect(turns.every((turn) => isPairStraight(turn.cards)), true);
      expect(turns.every((turn) => turn.cards.length == desiredLength), true);
      expect(turns[0].value, Card.getValue(CardFace.four));
      expect(turns[1].value, Card.getValue(CardFace.three));
    });
    test('phoenixComplexTest', () {
      var cards = <Card>[
        Card(CardFace.mahJong, Color.special),
        Card(CardFace.two, Color.black),
        Card(CardFace.two, Color.green),
        Card(CardFace.three, Color.green),
        Card(CardFace.three, Color.red),
        Card(CardFace.three, Color.black),
        Card(CardFace.four, Color.red),
        Card(CardFace.phoenix, Color.special),
        Card(CardFace.five, Color.red),
        Card(CardFace.five, Color.green),
        Card(CardFace.six, Color.red),
        Card(CardFace.six, Color.black),
        Card(CardFace.seven, Color.red),
        Card(CardFace.nine, Color.black)
      ];
      var desiredLength = 6;
      var turns = getPairStraights(cards, desiredLength);
      turns.sort(compareTurns);

      expect(turns.length, 5);
      expect(turns.every((turn) => isPairStraight(turn.cards)), true);
      expect(turns.every((turn) => turn.cards.length == desiredLength), true);
      expect(turns[0].value, Card.getValue(CardFace.seven));
      expect(turns[1].value, Card.getValue(CardFace.six));
      expect(turns[2].value, Card.getValue(CardFace.five));
      expect(turns[3].value, Card.getValue(CardFace.four));
      expect(turns[4].value, Card.getValue(CardFace.three));
    });
  });
  group('getPairStraightPermutations', () {
    final fourPairStraight = [
      Card(CardFace.two, Color.red),
      Card(CardFace.two, Color.green),
      Card(CardFace.three, Color.red),
      Card(CardFace.three, Color.black),
      Card(CardFace.four, Color.red),
      Card(CardFace.four, Color.black),
      Card(CardFace.five, Color.red),
      Card(CardFace.five, Color.green)
    ];
    test('standardTest', () {
      var turns = getPairStraightPermutations(fourPairStraight);

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
      var cards = <Card>[
        Card(CardFace.five, Color.black),
        Card(CardFace.five, Color.green),
        Card(CardFace.six, Color.blue),
        Card(CardFace.six, Color.green)
      ];

      expect(isPairStraight(cards), true);
    });
    test('threePairStraightPhoenixTest', () {
      var cards = <Card>[
        Card(CardFace.five, Color.black),
        Card(CardFace.five, Color.green),
        Card(CardFace.seven, Color.red),
        Card(CardFace.six, Color.blue),
        Card(CardFace.six, Color.green),
        Card.phoenix(Card.getValue(CardFace.seven))
      ];

      expect(isPairStraight(cards), true);
    });
    test('pairStraightOddCardsTest', () {
      var cards = <Card>[
        Card(CardFace.five, Color.black),
        Card(CardFace.five, Color.green),
        Card(CardFace.seven, Color.red),
        Card(CardFace.six, Color.blue),
        Card(CardFace.six, Color.green),
        Card.phoenix(Card.getValue(CardFace.seven)),
        Card(CardFace.eight, Color.black)
      ];

      expect(isPairStraight(cards), false);
    });
    test('pairStraightDogTest', () {
      var cards = <Card>[
        Card(CardFace.five, Color.black),
        Card(CardFace.five, Color.green),
        Card(CardFace.seven, Color.red),
        Card(CardFace.six, Color.blue),
        Card(CardFace.six, Color.green),
        Card.phoenix(Card.getValue(CardFace.seven)),
        Card(CardFace.dog, Color.special)
      ];

      expect(isPairStraight(cards), false);
    });
  });
}
