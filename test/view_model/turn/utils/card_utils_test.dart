import 'package:test/test.dart';
import "package:tichu/view_model/turn/utils/card_utils.dart";
import 'package:tichu/view_model/turn/tichu_data.dart';

void main() {
  group('occurrences', () {
    final cards = [
      Card(CardFace.nine, Color.red),
      Card(CardFace.nine, Color.green),
      Card(CardFace.nine, Color.green),
      Card(CardFace.king, Color.green)
    ];
    test('threeOccurrencesTest', () {
      expect(occurrences(CardFace.nine, cards), 3);
    });
    test('singleOccurrenceTest', () {
      expect(occurrences(CardFace.king, cards), 1);
    });
    test('noOccurrencesTest', () {
      expect(occurrences(CardFace.two, cards), 0);
    });
  });
  group('getOccurrenceCount', () {
    test('standardTest', () {
      final cards = [
        Card(CardFace.three, Color.green),
        Card(CardFace.three, Color.black),
        Card(CardFace.four, Color.red),
      ];
      var occurrences = getOccurrenceCount(cards);
      expect(occurrences.keys.length, 2);
      expect(occurrences.values.fold(0, (prev, element) => prev + element),
          cards.length);
      expect(occurrences[CardFace.three], 2);
      expect(occurrences[CardFace.four], 1);
    });
  });
  group('uniformColor', () {
    test('uniformColorTest', () {
      var cards = <Card>[
        Card(CardFace.five, Color.red),
        Card(CardFace.jack, Color.red),
        Card(CardFace.king, Color.red)
      ];

      expect(uniformColor(cards), true);
    });
    test('nonUniformColorsTest', () {
      var cards = <Card>[
        Card(CardFace.five, Color.red),
        Card(CardFace.jack, Color.red),
        Card(CardFace.dog, Color.special)
      ];

      expect(uniformColor(cards), false);
    });
  });
  group('findConnected', () {
    test('simple', () {
      final cards = [
        Card(CardFace.three, Color.green),
        Card(CardFace.four, Color.red),
        Card(CardFace.five, Color.red),
        Card(CardFace.seven, Color.red),
        Card(CardFace.eight, Color.red),
        Card(CardFace.king, Color.red),
      ];

      var expected = <ConnectedCards>[
        ConnectedCards(0, 0),
        ConnectedCards(1, 2),
        ConnectedCards(3, 5)
      ];
      var connectedCards = findConnectedCards(cards);

      expect(connectedCards.first.beginIdx, 0);
      expect(connectedCards.last.endIdx, cards.indexOf(cards.last));
      expect(connectedCards, expected);
    });
  });
}
