import 'package:test/test.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';
import 'package:tichu/view_model/turn/utils/full_house_utils.dart';

void main() {
  group('isFullHouse', () {
    test('standardSituationTest', () {
      var cards = <Card>[
        Card(CardFace.two, Color.black),
        Card(CardFace.two, Color.green),
        Card(CardFace.two, Color.red),
        Card(CardFace.five, Color.black),
        Card(CardFace.five, Color.green)
      ];

      expect(isFullHouse(cards), true);
    });
    test('phoenixTest', () {
      var cards = <Card>[
        Card.phoenix(5),
        Card(CardFace.two, Color.green),
        Card(CardFace.two, Color.red),
        Card(CardFace.five, Color.black),
        Card(CardFace.five, Color.green)
      ];

      expect(isFullHouse(cards), true);
    });
  });
  group('getFullHouses', () {
    test('twoTripletsTest', () {
      var cards = <Card>[
        Card(CardFace.two, Color.black),
        Card(CardFace.two, Color.green),
        Card(CardFace.two, Color.red),
        Card(CardFace.five, Color.black),
        Card(CardFace.five, Color.green),
        Card(CardFace.five, Color.red)
      ];

      var turns = getFullHouses(cards);

      expect(turns.length, 2);
      expect(turns.every((turn) => isFullHouse(turn.cards)), true);
      expect(
          turns.any((turn) => turn.value == Card.getValue(CardFace.two)), true);
      expect(turns.any((turn) => turn.value == Card.getValue(CardFace.five)),
          true);
    });
    test('twoPairsTest', () {
      var cards = <Card>[
        Card(CardFace.two, Color.black),
        Card(CardFace.two, Color.green),
        Card(CardFace.two, Color.red),
        Card(CardFace.five, Color.black),
        Card(CardFace.five, Color.green),
        Card(CardFace.seven, Color.red),
        Card(CardFace.seven, Color.black)
      ];

      var turns = getFullHouses(cards);

      expect(turns.length, 2);
      expect(turns.every((turn) => isFullHouse(turn.cards)), true);
      expect(turns.every((turn) => turn.value == Card.getValue(CardFace.two)),
          true);
      expect(
          turns.any(
              (turn) => turn.cards.any((card) => card.face == CardFace.five)),
          true);
      expect(
          turns.any(
              (turn) => turn.cards.any((card) => card.face == CardFace.seven)),
          true);
    });
    test('twoPairsPhoenixTest', () {
      var cards = <Card>[
        Card(CardFace.two, Color.black),
        Card(CardFace.two, Color.green),
        Card(CardFace.five, Color.black),
        Card(CardFace.five, Color.green),
        Card(CardFace.phoenix, Color.special),
        Card(CardFace.seven, Color.red),
        Card(CardFace.seven, Color.black)
      ];

      var turns = getFullHouses(cards);

      expect(turns.length, 6);
      expect(turns.every((turn) => isFullHouse(turn.cards)), true);
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
        Card(CardFace.two, Color.black),
        Card(CardFace.two, Color.green),
        Card(CardFace.two, Color.red),
        Card(CardFace.five, Color.black),
        Card(CardFace.five, Color.green),
        Card(CardFace.phoenix, Color.special),
        Card(CardFace.seven, Color.black)
      ];

      var turns = getFullHouses(cards);

      expect(turns.length, 3);
      expect(turns.every((turn) => isFullHouse(turn.cards)), true);
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
