import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn/utils/pair_straight_utils.dart';
import 'package:tichu/game/turn/tichu_data.dart';

void main() {
  group('getPairStraights', () {
    test('removeTripleCardsTest', () {
      var cards = <Card>[
        Card(CardFace.three, CardColor.green),
        Card(CardFace.three, CardColor.red),
        Card(CardFace.three, CardColor.black),
        Card(CardFace.four, CardColor.red),
        Card(CardFace.four, CardColor.black),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.six, CardColor.red),
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.eight, CardColor.red),
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
        Card(CardFace.two, CardColor.black),
        Card(CardFace.three, CardColor.green),
        Card(CardFace.three, CardColor.red),
        Card(CardFace.three, CardColor.black),
        Card(CardFace.four, CardColor.red),
        Card(CardFace.four, CardColor.black),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.six, CardColor.red),
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.seven, CardColor.green),
        Card(CardFace.eight, CardColor.red),
        Card(CardFace.eight, CardColor.black),
        Card(CardFace.nine, CardColor.black),
        Card(CardFace.nine, CardColor.red),
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
        Card(CardFace.three, CardColor.green),
        Card(CardFace.three, CardColor.red),
        Card(CardFace.four, CardColor.black),
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.five, CardColor.black),
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
        Card(CardFace.two, CardColor.black),
        Card(CardFace.three, CardColor.green),
        Card(CardFace.three, CardColor.red),
        Card(CardFace.four, CardColor.black),
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.six, CardColor.red),
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
        Card(CardFace.mahJong, CardColor.special),
        Card(CardFace.two, CardColor.black),
        Card(CardFace.two, CardColor.green),
        Card(CardFace.three, CardColor.green),
        Card(CardFace.three, CardColor.red),
        Card(CardFace.three, CardColor.black),
        Card(CardFace.four, CardColor.red),
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.six, CardColor.red),
        Card(CardFace.six, CardColor.black),
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.nine, CardColor.black),
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

    test('oddDesiredLengthReturnsEmpty', () {
      var cards = <Card>[
        Card(CardFace.two, CardColor.black),
        Card(CardFace.two, CardColor.green),
        Card(CardFace.three, CardColor.black),
        Card(CardFace.three, CardColor.green),
        Card(CardFace.four, CardColor.red),
        Card(CardFace.four, CardColor.green),
      ];

      var turns = getPairStraights(cards, 5);

      expect(turns, isEmpty);
    });
  });
  group('getPairStraightPermutations', () {
    final fourPairStraight = [
      Card(CardFace.two, CardColor.red),
      Card(CardFace.two, CardColor.green),
      Card(CardFace.three, CardColor.red),
      Card(CardFace.three, CardColor.black),
      Card(CardFace.four, CardColor.red),
      Card(CardFace.four, CardColor.black),
      Card(CardFace.five, CardColor.red),
      Card(CardFace.five, CardColor.green),
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
        Card(CardFace.five, CardColor.black),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.six, CardColor.green),
      ];

      expect(isPairStraight(cards), true);
    });
    test('threePairStraightPhoenixTest', () {
      var cards = <Card>[
        Card(CardFace.five, CardColor.black),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.six, CardColor.green),
        Card.phoenix(Card.getValue(CardFace.seven)),
      ];

      expect(isPairStraight(cards), true);
    });
    test('pairStraightOddCardsTest', () {
      var cards = <Card>[
        Card(CardFace.five, CardColor.black),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.six, CardColor.green),
        Card.phoenix(Card.getValue(CardFace.seven)),
        Card(CardFace.eight, CardColor.black),
      ];

      expect(isPairStraight(cards), false);
    });
    test('pairStraightDogTest', () {
      var cards = <Card>[
        Card(CardFace.five, CardColor.black),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.six, CardColor.green),
        Card.phoenix(Card.getValue(CardFace.seven)),
        Card(CardFace.dog, CardColor.special),
      ];

      expect(isPairStraight(cards), false);
    });
  });
}
