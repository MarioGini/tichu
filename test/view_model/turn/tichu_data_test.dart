import 'package:test/test.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';

void main() {
  test('Sorting test', () {
    var testCards = <Card>[
      Card(CardFace.dog, Color.special),
      Card(CardFace.ten, Color.black),
      Card(CardFace.eight, Color.red),
      Card(CardFace.phoenix, Color.special)
    ];
    testCards.sort(compareCards);

    var expectedOrder = <Card>[
      Card(CardFace.ten, Color.black),
      Card(CardFace.eight, Color.red),
      Card(CardFace.dog, Color.special),
      Card(CardFace.phoenix, Color.special)
    ];
    expect(testCards, expectedOrder);
  });
}
