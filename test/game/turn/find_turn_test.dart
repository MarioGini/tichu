import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn/find_turn.dart';
import 'package:tichu/game/turn/tichu_data.dart';

void main() {
  group('singles', () {
    test('standardTest', () {
      final testCard = Card(CardFace.seven, CardColor.black);
      expect(checkSingle(testCard), TichuTurn(TurnType.single, [testCard]));
    });
    test('phoenixTest', () {
      const testCard = Card.phoenix(8.5);
      expect(
        checkSingle(testCard),
        TichuTurn(TurnType.single, const [testCard]),
      );
    });
    test('dragonTest', () {
      final testCard = Card(CardFace.dragon, CardColor.special);
      expect(checkSingle(testCard), TichuTurn(TurnType.single, [testCard]));
    });
    test('dogTest', () {
      final testCard = Card(CardFace.dog, CardColor.special);
      expect(checkSingle(testCard), TichuTurn(TurnType.dog, [testCard]));
    });
  });
  group('pairs', () {
    test('standardTest', () {
      final cards = <Card>[
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.red),
      ];
      expect(checkForPair(cards), TichuTurn(TurnType.pair, cards));
    });
    test('phoenixInvalidTest', () {
      final cards = <Card>[
        Card(CardFace.five, CardColor.blue),
        const Card.phoenix(4),
      ];
      expect(checkForPair(cards), TichuTurn(TurnType.pair, cards));
    });
    test('phoenixFromHandSelection', () {
      final cards = <Card>[
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.phoenix, CardColor.special),
      ];
      final expected = <Card>[
        Card(CardFace.five, CardColor.blue),
        Card.phoenix(Card.getValue(CardFace.five)),
      ];
      expect(getTurn(cards), TichuTurn(TurnType.pair, expected));
    });
    test('phoenixValidTest', () {
      final cards = <Card>[
        Card(CardFace.five, CardColor.blue),
        const Card.phoenix(5),
      ];
      expect(checkForPair(cards), TichuTurn(TurnType.pair, cards));
    });

    test('dragonWithPhoenixIsInvalidPair', () {
      final cards = <Card>[
        Card(CardFace.dragon, CardColor.special),
        Card(CardFace.phoenix, CardColor.special),
      ];
      expect(getTurn(cards), TichuTurn.InvalidTurn());
    });

    test('mahjongWithPhoenixIsInvalidPair', () {
      final cards = <Card>[
        Card(CardFace.mahJong, CardColor.special),
        Card(CardFace.phoenix, CardColor.special),
      ];
      expect(getTurn(cards), TichuTurn.InvalidTurn());
    });
  });
  group('triplets', () {
    test('standardTest', () {
      final cards = <Card>[
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.five, CardColor.black),
      ];
      expect(checkForTriplet(cards), TichuTurn(TurnType.triplet, cards));
    });
    test('phoenixInvalidTest', () {
      final cards = <Card>[
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        const Card.phoenix(4),
      ];
      expect(checkForTriplet(cards), TichuTurn(TurnType.triplet, cards));
    });
    test('phoenixValidTest', () {
      final cards = <Card>[
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card.phoenix(Card.getValue(CardFace.five)),
      ];
      expect(checkForTriplet(cards), TichuTurn(TurnType.triplet, cards));
    });
    test('phoenixFromHandSelection', () {
      final cards = <Card>[
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.phoenix, CardColor.special),
      ];
      final expected = <Card>[
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card.phoenix(Card.getValue(CardFace.five)),
      ];
      expect(getTurn(cards), TichuTurn(TurnType.triplet, expected));
    });
  });
  group('quartets', () {
    test('bombTest', () {
      final cards = <Card>[
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.five, CardColor.green),
      ];
      expect(checkForQuartet(cards), TichuTurn(TurnType.bomb, cards));
    });
    test('pairStraightTest', () {
      // The list should be sorted.
      final cards = <Card>[
        Card(CardFace.six, CardColor.green),
        Card.phoenix(Card.getValue(CardFace.six)),
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.green),
      ];
      expect(checkForQuartet(cards), TichuTurn(TurnType.pairStraight, cards));
    });
  });
  group('fiveCards', () {
    test('standardStraightTest', () {
      final cards = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.seven, CardColor.green),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.eight, CardColor.green),
      ];
      expect(checkFives(cards), TichuTurn(TurnType.straight, cards));
    });
    test('phoenixStraightTest', () {
      final cards = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.five, CardColor.red),
        Card.phoenix(Card.getValue(CardFace.seven)),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.eight, CardColor.green),
      ];
      expect(checkFives(cards), TichuTurn(TurnType.straight, cards));
    });
    test('phoenixStraightFromHandSelection', () {
      final cards = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.eight, CardColor.green),
        Card(CardFace.phoenix, CardColor.special),
      ];
      final expected = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.eight, CardColor.green),
        Card.phoenix(Card.getValue(CardFace.seven)),
      ];
      expect(getTurn(cards), TichuTurn(TurnType.straight, expected));
    });
    test('straightBombTest', () {
      final cards = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.seven, CardColor.blue),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.eight, CardColor.blue),
      ];
      expect(checkFives(cards), TichuTurn(TurnType.bomb, cards));
    });
    test('fullHouseTest', () {
      final cards = <Card>[
        Card(CardFace.four, CardColor.black),
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.four, CardColor.green),
        Card(CardFace.six, CardColor.blue),
        Card.phoenix(Card.getValue(CardFace.six)),
      ];
      expect(checkFives(cards), TichuTurn(TurnType.fullHouse, cards));
    });
    test('fullHouseFromHandSelection', () {
      final cards = <Card>[
        Card(CardFace.four, CardColor.black),
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.four, CardColor.green),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.phoenix, CardColor.special),
      ];
      final expected = <Card>[
        Card(CardFace.four, CardColor.black),
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.four, CardColor.green),
        Card(CardFace.six, CardColor.blue),
        Card.phoenix(Card.getValue(CardFace.six)),
      ];
      expect(getTurn(cards), TichuTurn(TurnType.fullHouse, expected));
    });
  });
  group('checkBigTurns', () {
    test('eightStraightTest', () {
      final cards = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.jack, CardColor.blue),
        Card(CardFace.seven, CardColor.blue),
        Card(CardFace.eight, CardColor.blue),
        Card(CardFace.nine, CardColor.blue),
        Card(CardFace.ten, CardColor.blue),
      ];
      expect(checkBigTurns(cards), TichuTurn(TurnType.straight, cards));
    });
    test('fourPairStraightTest', () {
      final cards = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.four, CardColor.green),
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.six, CardColor.black),
        Card(CardFace.seven, CardColor.blue),
        Card(CardFace.seven, CardColor.red),
      ];
      expect(checkBigTurns(cards), TichuTurn(TurnType.pairStraight, cards));
    });
    test('pairStraightFromHandSelection', () {
      final cards = <Card>[
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.six, CardColor.green),
        Card(CardFace.phoenix, CardColor.special),
      ];
      final expected = <Card>[
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.six, CardColor.green),
        Card.phoenix(Card.getValue(CardFace.six)),
      ];
      expect(getTurn(cards), TichuTurn(TurnType.pairStraight, expected));
    });
    test('sixStraightBombTest', () {
      final cards = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.seven, CardColor.blue),
        Card(CardFace.eight, CardColor.blue),
        Card(CardFace.nine, CardColor.blue),
      ];
      expect(checkBigTurns(cards), TichuTurn(TurnType.bomb, cards));
    });
  });
  group('getTurn', () {
    test('singleTest', () {
      final cards = <Card>[Card(CardFace.four, CardColor.blue)];
      expect(getTurn(cards), TichuTurn(TurnType.single, cards));
    });
    test('pairTest', () {
      final cards = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.four, CardColor.red),
      ];
      expect(getTurn(cards), TichuTurn(TurnType.pair, cards));
    });
    test('twoPairsTest', () {
      final cards = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.four, CardColor.green),
        Card(CardFace.five, CardColor.blue),
        Card.phoenix(Card.getValue(CardFace.five)),
      ];
      expect(getTurn(cards), TichuTurn(TurnType.pairStraight, cards));
    });
    test('phoenixMismatchedValueStillFormsTriplet', () {
      final cards = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.four, CardColor.green),
        Card.phoenix(Card.getValue(CardFace.five)),
      ];
      expect(getTurn(cards), TichuTurn(TurnType.triplet, cards));
    });
    test('straightFromHandSelection', () {
      final cards = <Card>[
        Card(CardFace.nine, CardColor.blue),
        Card(CardFace.eight, CardColor.green),
        Card(CardFace.seven, CardColor.blue),
        Card(CardFace.six, CardColor.red),
        Card(CardFace.phoenix, CardColor.special),
      ];
      final expected = <Card>[
        Card(CardFace.nine, CardColor.blue),
        Card(CardFace.eight, CardColor.green),
        Card(CardFace.seven, CardColor.blue),
        Card(CardFace.six, CardColor.red),
        Card.phoenix(Card.getValue(CardFace.ten)),
      ];
      expect(getTurn(cards), TichuTurn(TurnType.straight, expected));
    });
    test('invalidStraightTest', () {
      final cards = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card.phoenix(Card.getValue(CardFace.five)),
        Card(CardFace.six, CardColor.red),
        Card(CardFace.seven, CardColor.blue),
        Card(CardFace.nine, CardColor.green),
      ];
      expect(getTurn(cards), TichuTurn.InvalidTurn());
    });
    test('threePairStraightTest', () {
      final cards = <Card>[
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.four, CardColor.red),
        Card(CardFace.five, CardColor.red),
        Card.phoenix(Card.getValue(CardFace.five)),
        Card(CardFace.six, CardColor.black),
        Card(CardFace.six, CardColor.red),
      ];
      expect(getTurn(cards), TichuTurn(TurnType.pairStraight, cards));
    });

    test('invalid when two phoenix cards are present', () {
      final cards = <Card>[
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.red),
        Card.phoenix(Card.getValue(CardFace.five)),
        Card.phoenix(Card.getValue(CardFace.five)),
      ];
      expect(getTurn(cards), TichuTurn.InvalidTurn());
    });

    test('phoenix resolves as straight in six-card hand', () {
      final cards = <Card>[
        Card(CardFace.two, CardColor.blue),
        Card(CardFace.three, CardColor.red),
        Card(CardFace.four, CardColor.green),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.seven, CardColor.blue),
        Card(CardFace.phoenix, CardColor.special),
      ];

      final turn = getTurn(cards);
      expect(turn.type, TurnType.straight);
      expect(turn.cards, hasLength(6));
    });

    test('phoenix resolves in long pair-straight when possible', () {
      final cards = <Card>[
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.six, CardColor.green),
        Card(CardFace.six, CardColor.black),
        Card(CardFace.seven, CardColor.blue),
        Card(CardFace.phoenix, CardColor.special),
      ];

      final turn = getTurn(cards);
      expect(turn.type, TurnType.pairStraight);
    });
  });
}
