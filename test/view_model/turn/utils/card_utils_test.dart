import 'package:test/test.dart';
import "package:tichu/view_model/turn/utils/card_utils.dart";
import 'package:tichu/view_model/turn/tichu_data.dart';

void main() {
  group('occurrences', () {
    final List<Card> cards = [
      Card(CardFace.NINE, Color.RED),
      Card(CardFace.NINE, Color.GREEN),
      Card(CardFace.NINE, Color.GREEN),
      Card(CardFace.KING, Color.GREEN)
    ];
    test('threeOccurrencesTest', () {
      expect(occurrences(CardFace.NINE, cards), 3);
    });
    test('singleOccurrenceTest', () {
      expect(occurrences(CardFace.KING, cards), 1);
    });
    test('noOccurrencesTest', () {
      expect(occurrences(CardFace.TWO, cards), 0);
    });
  });
  group('uniformColor', () {
    test('uniformColorTest', () {
      List<Card> cards = [
        Card(CardFace.FIVE, Color.RED),
        Card(CardFace.JACK, Color.RED),
        Card(CardFace.KING, Color.RED)
      ];

      expect(uniformColor(cards), true);
    });
    test('nonUniformColorsTest', () {
      List<Card> cards = [
        Card(CardFace.FIVE, Color.RED),
        Card(CardFace.JACK, Color.RED),
        Card(CardFace.DOG, Color.SPECIAL)
      ];

      expect(uniformColor(cards), false);
    });
  });
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
}
