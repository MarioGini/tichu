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
      expect(turns.any((element) => element.value == cards.first.value), true);
      expect(turns.any((element) => element.value == cards.last.value), true);
    });
  });
}
