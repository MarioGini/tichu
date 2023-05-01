import 'package:test/test.dart';
import 'package:tichu/view_model/turn/find_turn.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';

void main() {
  group('singles', () {
    test('standardTest', () {
      var testCard = Card(CardFace.seven, Color.black);
      expect(checkSingle(testCard), TichuTurn(TurnType.single, [testCard]));
    });
    test('phoenixTest', () {
      var testCard = Card.phoenix(8.5);
      expect(checkSingle(testCard), TichuTurn(TurnType.single, [testCard]));
    });
    test('dragonTest', () {
      var testCard = Card(CardFace.dragon, Color.special);
      expect(checkSingle(testCard), TichuTurn(TurnType.single, [testCard]));
    });
    test('dogTest', () {
      var testCard = Card(CardFace.dog, Color.special);
      expect(checkSingle(testCard), TichuTurn(TurnType.dog, [testCard]));
    });
  });
  group('pairs', () {
    test('standardTest', () {
      var cards = <Card>[
        Card(CardFace.five, Color.blue),
        Card(CardFace.five, Color.red)
      ];
      expect(checkForPair(cards), TichuTurn(TurnType.pair, cards));
    });
    test('phoenixInvalidTest', () {
      var cards = <Card>[Card(CardFace.five, Color.blue), Card.phoenix(4)];
      expect(checkForPair(cards), TichuTurn.InvalidTurn());
    });
    test('phoenixValidTest', () {
      var cards = <Card>[Card(CardFace.five, Color.blue), Card.phoenix(5)];
      expect(checkForPair(cards), TichuTurn(TurnType.pair, cards));
    });
  });
  group('triplets', () {
    test('standardTest', () {
      var cards = <Card>[
        Card(CardFace.five, Color.blue),
        Card(CardFace.five, Color.red),
        Card(CardFace.five, Color.black),
      ];
      expect(checkForTriplet(cards), TichuTurn(TurnType.triplet, cards));
    });
    test('phoenixInvalidTest', () {
      var cards = <Card>[
        Card(CardFace.five, Color.blue),
        Card(CardFace.five, Color.green),
        Card.phoenix(4.0)
      ];
      expect(checkForTriplet(cards), TichuTurn.InvalidTurn());
    });
    test('phoenixValidTest', () {
      var cards = <Card>[
        Card(CardFace.five, Color.blue),
        Card(CardFace.five, Color.green),
        Card.phoenix(Card.getValue(CardFace.five))
      ];
      expect(checkForTriplet(cards), TichuTurn(TurnType.triplet, cards));
    });
  });
  group('quartets', () {
    test('bombTest', () {
      var cards = <Card>[
        Card(CardFace.five, Color.blue),
        Card(CardFace.five, Color.red),
        Card(CardFace.five, Color.black),
        Card(CardFace.five, Color.green),
      ];
      expect(checkForQuartet(cards), TichuTurn(TurnType.bomb, cards));
    });
    test('pairStraightTest', () {
      // The list should be sorted.
      var cards = <Card>[
        Card(CardFace.six, Color.green),
        Card.phoenix(Card.getValue(CardFace.six)),
        Card(CardFace.five, Color.blue),
        Card(CardFace.five, Color.green)
      ];
      expect(checkForQuartet(cards), TichuTurn(TurnType.pairStraight, cards));
    });
  });
  group('fiveCards', () {
    test('standardStraightTest', () {
      var cards = <Card>[
        Card(CardFace.four, Color.blue),
        Card(CardFace.five, Color.red),
        Card(CardFace.seven, Color.green),
        Card(CardFace.six, Color.blue),
        Card(CardFace.eight, Color.green)
      ];
      expect(checkFives(cards), TichuTurn(TurnType.straight, cards));
    });
    test('phoenixStraightTest', () {
      var cards = <Card>[
        Card(CardFace.four, Color.blue),
        Card(CardFace.five, Color.red),
        Card.phoenix(Card.getValue(CardFace.seven)),
        Card(CardFace.six, Color.blue),
        Card(CardFace.eight, Color.green)
      ];
      expect(checkFives(cards), TichuTurn(TurnType.straight, cards));
    });
    test('straightBombTest', () {
      var cards = <Card>[
        Card(CardFace.four, Color.blue),
        Card(CardFace.five, Color.blue),
        Card(CardFace.seven, Color.blue),
        Card(CardFace.six, Color.blue),
        Card(CardFace.eight, Color.blue)
      ];
      expect(checkFives(cards), TichuTurn(TurnType.bomb, cards));
    });
    test('fullHouseTest', () {
      var cards = <Card>[
        Card(CardFace.four, Color.black),
        Card(CardFace.four, Color.blue),
        Card(CardFace.four, Color.green),
        Card(CardFace.six, Color.blue),
        Card.phoenix(Card.getValue(CardFace.six))
      ];
      expect(checkFives(cards), TichuTurn(TurnType.fullHouse, cards));
    });
  });
  group('checkBigTurns', () {
    test('eightStraightTest', () {
      var cards = <Card>[
        Card(CardFace.four, Color.blue),
        Card(CardFace.five, Color.green),
        Card(CardFace.six, Color.blue),
        Card(CardFace.jack, Color.blue),
        Card(CardFace.seven, Color.blue),
        Card(CardFace.eight, Color.blue),
        Card(CardFace.nine, Color.blue),
        Card(CardFace.ten, Color.blue)
      ];
      expect(checkBigTurns(cards), TichuTurn(TurnType.straight, cards));
    });
    test('fourPairStraightTest', () {
      var cards = <Card>[
        Card(CardFace.four, Color.blue),
        Card(CardFace.four, Color.green),
        Card(CardFace.five, Color.blue),
        Card(CardFace.six, Color.blue),
        Card(CardFace.five, Color.black),
        Card(CardFace.six, Color.black),
        Card(CardFace.seven, Color.blue),
        Card(CardFace.seven, Color.red)
      ];
      expect(checkBigTurns(cards), TichuTurn(TurnType.pairStraight, cards));
    });
    test('sixStraightBombTest', () {
      var cards = <Card>[
        Card(CardFace.four, Color.blue),
        Card(CardFace.five, Color.blue),
        Card(CardFace.six, Color.blue),
        Card(CardFace.seven, Color.blue),
        Card(CardFace.eight, Color.blue),
        Card(CardFace.nine, Color.blue)
      ];
      expect(checkBigTurns(cards), TichuTurn(TurnType.bomb, cards));
    });
  });
  group('getTurn', () {
    test('singleTest', () {
      var cards = <Card>[Card(CardFace.four, Color.blue)];
      expect(getTurn(cards), TichuTurn(TurnType.single, cards));
    });
    test('pairTest', () {
      var cards = <Card>[
        Card(CardFace.four, Color.blue),
        Card(CardFace.four, Color.red)
      ];
      expect(getTurn(cards), TichuTurn(TurnType.pair, cards));
    });
    test('twoPairsTest', () {
      var cards = <Card>[
        Card(CardFace.four, Color.blue),
        Card(CardFace.four, Color.green),
        Card(CardFace.five, Color.blue),
        Card.phoenix(Card.getValue(CardFace.five))
      ];
      expect(getTurn(cards), TichuTurn(TurnType.pairStraight, cards));
    });
    test('invalidTripletTest', () {
      var cards = <Card>[
        Card(CardFace.four, Color.blue),
        Card(CardFace.four, Color.green),
        Card.phoenix(Card.getValue(CardFace.five))
      ];
      expect(getTurn(cards), TichuTurn.InvalidTurn());
    });
    test('invalidStraightTest', () {
      var cards = <Card>[
        Card(CardFace.four, Color.blue),
        Card.phoenix(Card.getValue(CardFace.five)),
        Card(CardFace.six, Color.red),
        Card(CardFace.seven, Color.blue),
        Card(CardFace.nine, Color.green),
      ];
      expect(getTurn(cards), TichuTurn.InvalidTurn());
    });
    test('threePairStraightTest', () {
      var cards = <Card>[
        Card(CardFace.four, Color.blue),
        Card(CardFace.four, Color.red),
        Card(CardFace.five, Color.red),
        Card.phoenix(Card.getValue(CardFace.five)),
        Card(CardFace.six, Color.black),
        Card(CardFace.six, Color.red),
      ];
      expect(getTurn(cards), TichuTurn(TurnType.pairStraight, cards));
    });
  });
}
