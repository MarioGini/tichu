import 'package:test/test.dart';
import 'package:tichu/view_model/tichu/tichu_data.dart';

void main() {
  test('Sorting test', () {
    List<Card> testCards = [
      Card(CardFace.DOG, Color.SPECIAL),
      Card(CardFace.TEN, Color.BLACK),
      Card(CardFace.EIGHT, Color.RED),
      Card(CardFace.PHOENIX, Color.SPECIAL)
    ];
    testCards.sort(compareCards);

    List<Card> expectedOrder = [
      Card(CardFace.TEN, Color.BLACK),
      Card(CardFace.EIGHT, Color.RED),
      Card(CardFace.DOG, Color.SPECIAL),
      Card(CardFace.PHOENIX, Color.SPECIAL)
    ];
    expect(testCards, expectedOrder);
  });
}
