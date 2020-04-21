import 'package:test/test.dart';
import "package:tichu/view_model/tichu/card_utils.dart";
import 'package:tichu/view_model/tichu/tichu_data.dart';

void main() {
  group('countOccurrences', () {
    List<Card> cards;
    setUp(() {
      cards = [Card.NINE, Card.FOUR];
    });
    test('noOccurrence', () {
      expect(countOccurrence(cards, Card.FIVE), 0);
    });

    test('oneOccurrence', () {
      expect(countOccurrence(cards, Card.NINE), 1);
    });
  });
}
