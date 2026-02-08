import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/view_model/turn/find_turn.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';

void main() {
  group('singles', () {
    test('standardTest', () {
      var testCard = Card(CardFace.seven, CardColor.black);
      expect(checkSingle(testCard), TichuTurn(TurnType.single, [testCard]));
    });
    test('phoenixTest', () {
      var testCard = Card.phoenix(8.5);
      expect(checkSingle(testCard), TichuTurn(TurnType.single, [testCard]));
    });
    test('dragonTest', () {
      var testCard = Card(CardFace.dragon, CardColor.special);
      expect(checkSingle(testCard), TichuTurn(TurnType.single, [testCard]));
    });
    test('dogTest', () {
      var testCard = Card(CardFace.dog, CardColor.special);
      expect(checkSingle(testCard), TichuTurn(TurnType.dog, [testCard]));
    });
  });
  group('pairs', () {
    test('standardTest', () {
      var cards = <Card>[
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.red)
      ];
      expect(checkForPair(cards), TichuTurn(TurnType.pair, cards));
    });
    test('phoenixInvalidTest', () {
      var cards = <Card>[Card(CardFace.five, CardColor.blue), Card.phoenix(4)];
      expect(checkForPair(cards), TichuTurn.InvalidTurn());
    });
    test('phoenixValidTest', () {
      var cards = <Card>[Card(CardFace.five, CardColor.blue), Card.phoenix(5)];
      expect(checkForPair(cards), TichuTurn(TurnType.pair, cards));
    });
  });
  group('triplets', () {
    test('standardTest', () {
      var cards = <Card>[
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.five, CardColor.black),
      ];
      expect(checkForTriplet(cards), TichuTurn(TurnType.triplet, cards));
    });
    test('phoenixInvalidTest', () {
      var cards = <Card>[
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card.phoenix(4.0)
      ];
      expect(checkForTriplet(cards), TichuTurn.InvalidTurn());
    });
    test('phoenixValidTest', () {
      var cards = <Card>[
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card.phoenix(Card.getValue(CardFace.five))
      ];
      expect(checkForTriplet(cards), TichuTurn(TurnType.triplet, cards));
    });
  });
  group('quartets', () {
    test('bombTest', () {
      var cards = <Card>[
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.five, CardColor.green),
      ];
      expect(checkForQuartet(cards), TichuTurn(TurnType.bomb, cards));
    });
    test('pairStraightTest', () {
      // The list should be sorted.
      var cards = <Card>[
        Card(CardFace.six, CardColor.green),
        Card.phoenix(Card.getValue(CardFace.six)),
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.green)
      ];
      expect(checkForQuartet(cards), TichuTurn(TurnType.pairStraight, cards));
    });
  });
  group('fiveCards', () {
    test('standardStraightTest', () {
      var cards = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.seven, CardColor.green),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.eight, CardColor.green)
      ];
      expect(checkFives(cards), TichuTurn(TurnType.straight, cards));
    });
    test('phoenixStraightTest', () {
      var cards = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.five, CardColor.red),
        Card.phoenix(Card.getValue(CardFace.seven)),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.eight, CardColor.green)
      ];
      expect(checkFives(cards), TichuTurn(TurnType.straight, cards));
    });
    test('straightBombTest', () {
      var cards = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.seven, CardColor.blue),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.eight, CardColor.blue)
      ];
      expect(checkFives(cards), TichuTurn(TurnType.bomb, cards));
    });
    test('fullHouseTest', () {
      var cards = <Card>[
        Card(CardFace.four, CardColor.black),
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.four, CardColor.green),
        Card(CardFace.six, CardColor.blue),
        Card.phoenix(Card.getValue(CardFace.six))
      ];
      expect(checkFives(cards), TichuTurn(TurnType.fullHouse, cards));
    });
  });
  group('checkBigTurns', () {
    test('eightStraightTest', () {
      var cards = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.jack, CardColor.blue),
        Card(CardFace.seven, CardColor.blue),
        Card(CardFace.eight, CardColor.blue),
        Card(CardFace.nine, CardColor.blue),
        Card(CardFace.ten, CardColor.blue)
      ];
      expect(checkBigTurns(cards), TichuTurn(TurnType.straight, cards));
    });
    test('fourPairStraightTest', () {
      var cards = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.four, CardColor.green),
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.six, CardColor.black),
        Card(CardFace.seven, CardColor.blue),
        Card(CardFace.seven, CardColor.red)
      ];
      expect(checkBigTurns(cards), TichuTurn(TurnType.pairStraight, cards));
    });
    test('sixStraightBombTest', () {
      var cards = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.seven, CardColor.blue),
        Card(CardFace.eight, CardColor.blue),
        Card(CardFace.nine, CardColor.blue)
      ];
      expect(checkBigTurns(cards), TichuTurn(TurnType.bomb, cards));
    });
  });
  group('getTurn', () {
    test('singleTest', () {
      var cards = <Card>[Card(CardFace.four, CardColor.blue)];
      expect(getTurn(cards), TichuTurn(TurnType.single, cards));
    });
    test('pairTest', () {
      var cards = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.four, CardColor.red)
      ];
      expect(getTurn(cards), TichuTurn(TurnType.pair, cards));
    });
    test('twoPairsTest', () {
      var cards = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.four, CardColor.green),
        Card(CardFace.five, CardColor.blue),
        Card.phoenix(Card.getValue(CardFace.five))
      ];
      expect(getTurn(cards), TichuTurn(TurnType.pairStraight, cards));
    });
    test('invalidTripletTest', () {
      var cards = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.four, CardColor.green),
        Card.phoenix(Card.getValue(CardFace.five))
      ];
      expect(getTurn(cards), TichuTurn.InvalidTurn());
    });
    test('invalidStraightTest', () {
      var cards = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card.phoenix(Card.getValue(CardFace.five)),
        Card(CardFace.six, CardColor.red),
        Card(CardFace.seven, CardColor.blue),
        Card(CardFace.nine, CardColor.green),
      ];
      expect(getTurn(cards), TichuTurn.InvalidTurn());
    });
    test('threePairStraightTest', () {
      var cards = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.four, CardColor.red),
        Card(CardFace.five, CardColor.red),
        Card.phoenix(Card.getValue(CardFace.five)),
        Card(CardFace.six, CardColor.black),
        Card(CardFace.six, CardColor.red),
      ];
      expect(getTurn(cards), TichuTurn(TurnType.pairStraight, cards));
    });
  });
}
