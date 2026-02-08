import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';
import 'package:tichu/view_model/turn/utils/full_house_utils.dart';

void main() {
  group('getFullHouses', () {
    test('returnsEmptyWhenLessThanFiveCards', () {
      var cards = <Card>[
        Card(CardFace.two, CardColor.black),
        Card(CardFace.two, CardColor.green),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.five, CardColor.green),
      ];

      var turns = getFullHouses(cards);

      expect(turns, isEmpty);
    });

    test('ignoresDragonAndDogCards', () {
      var cards = <Card>[
        Card(CardFace.two, CardColor.black),
        Card(CardFace.two, CardColor.green),
        Card(CardFace.two, CardColor.red),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.dragon, CardColor.special),
        Card(CardFace.dog, CardColor.special),
      ];

      var turns = getFullHouses(cards);

      expect(turns.length, 1);
      expect(turns.first.type, TurnType.fullHouse);
      expect(
        turns.first.cards.any(
          (card) => card.face == CardFace.dragon || card.face == CardFace.dog,
        ),
        false,
      );
    });

    test('twoTripletsTest', () {
      var cards = <Card>[
        Card(CardFace.two, CardColor.black),
        Card(CardFace.two, CardColor.green),
        Card(CardFace.two, CardColor.red),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.five, CardColor.red),
      ];

      var turns = getFullHouses(cards);

      expect(turns.length, 2);
      expect(turns.every((turn) => turn.type == TurnType.fullHouse), true);
      expect(
        turns.any((turn) => turn.value == Card.getValue(CardFace.two)),
        true,
      );
      expect(
        turns.any((turn) => turn.value == Card.getValue(CardFace.five)),
        true,
      );
    });
    test('twoPairsTest', () {
      var cards = <Card>[
        Card(CardFace.two, CardColor.black),
        Card(CardFace.two, CardColor.green),
        Card(CardFace.two, CardColor.red),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.seven, CardColor.black),
      ];

      var turns = getFullHouses(cards);

      expect(turns.length, 2);
      expect(turns.every((turn) => turn.type == TurnType.fullHouse), true);
      expect(
        turns.every((turn) => turn.value == Card.getValue(CardFace.two)),
        true,
      );
      expect(
        turns.any(
          (turn) => turn.cards.any((card) => card.face == CardFace.five),
        ),
        true,
      );
      expect(
        turns.any(
          (turn) => turn.cards.any((card) => card.face == CardFace.seven),
        ),
        true,
      );
    });
    test('twoPairsPhoenixTest', () {
      var cards = <Card>[
        Card(CardFace.two, CardColor.black),
        Card(CardFace.two, CardColor.green),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.seven, CardColor.black),
      ];

      var turns = getFullHouses(cards);

      expect(turns.length, 6);
      expect(turns.every((turn) => turn.type == TurnType.fullHouse), true);
      var sevenFullHouseCount = turns
          .where((element) => element.value == Card.getValue(CardFace.seven))
          .length;
      var fiveFullHouseCount = turns
          .where((element) => element.value == Card.getValue(CardFace.five))
          .length;
      var twoFullHouseCount = turns
          .where((element) => element.value == Card.getValue(CardFace.two))
          .length;
      expect(sevenFullHouseCount, 2);
      expect(fiveFullHouseCount, 2);
      expect(twoFullHouseCount, 2);
    });
    test('tripletPhoenixTest', () {
      var cards = <Card>[
        Card(CardFace.two, CardColor.black),
        Card(CardFace.two, CardColor.green),
        Card(CardFace.two, CardColor.red),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.seven, CardColor.black),
      ];

      var turns = getFullHouses(cards);

      expect(turns.length, 3);
      expect(turns.every((turn) => turn.type == TurnType.fullHouse), true);
      var fiveFullHouseCount = turns
          .where((element) => element.value == Card.getValue(CardFace.five))
          .length;
      var twoFullHouseCount = turns
          .where((element) => element.value == Card.getValue(CardFace.two))
          .length;
      expect(fiveFullHouseCount, 1);
      expect(twoFullHouseCount, 2);
    });
  });
}
