import 'package:test/test.dart';
import "package:tichu/view_model/tichu/card_utils.dart";
import 'package:tichu/view_model/tichu/tichu_data.dart';

void main() {
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
  group('areOrdered', () {
    test('orderedWith', () {
      List<Card> cards = [
        Card(CardFace.FIVE, Color.BLACK),
        Card(CardFace.FOUR, Color.GREEN),
        Card(CardFace.THREE, Color.BLUE)
      ];

      expect(areOrdered(cards), true);
    });
    test('orderedWithDragon', () {
      List<Card> cards = [
        Card(CardFace.FIVE, Color.BLACK),
        Card(CardFace.FOUR, Color.GREEN),
        Card(CardFace.THREE, Color.BLUE),
        Card(CardFace.DRAGON, Color.SPECIAL)
      ];

      expect(areOrdered(cards), false);
    });
  });
}
