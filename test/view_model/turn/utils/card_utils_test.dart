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
  group('findConnected', () {
    test('simple', () {
      final List<Card> cards = [
        Card(CardFace.THREE, Color.GREEN),
        Card(CardFace.FOUR, Color.RED),
        Card(CardFace.FIVE, Color.RED),
        Card(CardFace.SEVEN, Color.RED),
        Card(CardFace.EIGHT, Color.RED),
        Card(CardFace.KING, Color.RED),
      ];

      List<ConnectedCards> expected = [
        ConnectedCards(0, 0),
        ConnectedCards(1, 2),
        ConnectedCards(3, 5)
      ];
      List<ConnectedCards> connectedCards = findConnectedCards(cards);

      expect(connectedCards.first.beginIdx, 0);
      expect(connectedCards.last.endIdx, cards.indexOf(cards.last));
      expect(connectedCards, expected);
    });
  });
}
