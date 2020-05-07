import 'package:test/test.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';
import "package:tichu/view_model/turn/utils/full_house_utils.dart";

void main() {
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
  group('getFullHouses', () {
    test('twoTripletsTest', () {
      List<Card> cards = [
        Card(CardFace.TWO, Color.BLACK),
        Card(CardFace.TWO, Color.GREEN),
        Card(CardFace.TWO, Color.RED),
        Card(CardFace.FIVE, Color.BLACK),
        Card(CardFace.FIVE, Color.GREEN),
        Card(CardFace.FIVE, Color.RED)
      ];

      List<TichuTurn> turns = getFullHouses(cards);

      expect(turns.length, 2);
      expect(turns.every((turn) => isFullHouse(turn.cards)), true);
      expect(
          turns.any((turn) => turn.value == Card.getValue(CardFace.TWO)), true);
      expect(turns.any((turn) => turn.value == Card.getValue(CardFace.FIVE)),
          true);
    });
    test('twoPairsTest', () {
      List<Card> cards = [
        Card(CardFace.TWO, Color.BLACK),
        Card(CardFace.TWO, Color.GREEN),
        Card(CardFace.TWO, Color.RED),
        Card(CardFace.FIVE, Color.BLACK),
        Card(CardFace.FIVE, Color.GREEN),
        Card(CardFace.SEVEN, Color.RED),
        Card(CardFace.SEVEN, Color.BLACK)
      ];

      List<TichuTurn> turns = getFullHouses(cards);

      expect(turns.length, 2);
      expect(turns.every((turn) => isFullHouse(turn.cards)), true);
      expect(turns.every((turn) => turn.value == Card.getValue(CardFace.TWO)),
          true);
      expect(
          turns.any(
              (turn) => turn.cards.any((card) => card.face == CardFace.FIVE)),
          true);
      expect(
          turns.any(
              (turn) => turn.cards.any((card) => card.face == CardFace.SEVEN)),
          true);
    });
    test('twoPairsPhoenixTest', () {
      List<Card> cards = [
        Card(CardFace.TWO, Color.BLACK),
        Card(CardFace.TWO, Color.GREEN),
        Card(CardFace.FIVE, Color.BLACK),
        Card(CardFace.FIVE, Color.GREEN),
        Card(CardFace.PHOENIX, Color.SPECIAL),
        Card(CardFace.SEVEN, Color.RED),
        Card(CardFace.SEVEN, Color.BLACK)
      ];

      List<TichuTurn> turns = getFullHouses(cards);

      expect(turns.length, 6);
      expect(turns.every((turn) => isFullHouse(turn.cards)), true);
      int sevenFullHouseCount = turns
          .where((element) => element.value == Card.getValue(CardFace.SEVEN))
          .length;
      int fiveFullHouseCount = turns
          .where((element) => element.value == Card.getValue(CardFace.FIVE))
          .length;
      int twoFullHouseCount = turns
          .where((element) => element.value == Card.getValue(CardFace.TWO))
          .length;
      expect(sevenFullHouseCount, 2);
      expect(fiveFullHouseCount, 2);
      expect(twoFullHouseCount, 2);
    });
    test('tripletPhoenixTest', () {
      List<Card> cards = [
        Card(CardFace.TWO, Color.BLACK),
        Card(CardFace.TWO, Color.GREEN),
        Card(CardFace.TWO, Color.RED),
        Card(CardFace.FIVE, Color.BLACK),
        Card(CardFace.FIVE, Color.GREEN),
        Card(CardFace.PHOENIX, Color.SPECIAL),
        Card(CardFace.SEVEN, Color.BLACK)
      ];

      List<TichuTurn> turns = getFullHouses(cards);

      expect(turns.length, 3);
      expect(turns.every((turn) => isFullHouse(turn.cards)), true);
      int fiveFullHouseCount = turns
          .where((element) => element.value == Card.getValue(CardFace.FIVE))
          .length;
      int twoFullHouseCount = turns
          .where((element) => element.value == Card.getValue(CardFace.TWO))
          .length;
      expect(fiveFullHouseCount, 1);
      expect(twoFullHouseCount, 2);
    });
  });
}
