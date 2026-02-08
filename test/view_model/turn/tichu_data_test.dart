import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';

void main() {
  test('Sorting test', () {
    var testCards = <Card>[
      Card(CardFace.dog, CardColor.special),
      Card(CardFace.ten, CardColor.black),
      Card(CardFace.eight, CardColor.red),
      Card(CardFace.phoenix, CardColor.special),
    ];
    testCards.sort(compareCards);

    var expectedOrder = <Card>[
      Card(CardFace.ten, CardColor.black),
      Card(CardFace.eight, CardColor.red),
      Card(CardFace.dog, CardColor.special),
      Card(CardFace.phoenix, CardColor.special),
    ];
    expect(testCards, expectedOrder);
  });
}
