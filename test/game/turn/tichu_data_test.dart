import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn/tichu_data.dart';

void main() {
  test('Sorting test', () {
    final testCards = <Card>[
      Card(CardFace.dog, CardColor.special),
      Card(CardFace.ten, CardColor.black),
      Card(CardFace.eight, CardColor.red),
      Card(CardFace.phoenix, CardColor.special),
    ];
    testCards.sort(compareCards);

    final expectedOrder = <Card>[
      Card(CardFace.ten, CardColor.black),
      Card(CardFace.eight, CardColor.red),
      Card(CardFace.dog, CardColor.special),
      Card(CardFace.phoenix, CardColor.special),
    ];
    expect(testCards, expectedOrder);
  });
}
