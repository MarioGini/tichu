import 'package:test/test.dart';
import 'package:tichu/view_model/tichu_data.dart';

void main() {
  test('Sorting test', () {
    List<Card> testCards = [Card.DOG, Card.TEN, Card.EIGHT, Card.PHOENIX];
    testCards.sort(compareCards);

    List<Card> expectedOrder = [Card.EIGHT, Card.TEN, Card.DOG, Card.PHOENIX];
    expect(testCards, expectedOrder);
  });

  group('GetTurnTests', () {
    test('SingleCardTests', () {});
  });
}
