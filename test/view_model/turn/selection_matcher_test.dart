import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/view_model/turn/selection_matcher.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';

void main() {
  group('selectionMatchesTurn', () {
    test('matches straight regardless of suit', () {
      final turnCards = [
        Card(CardFace.six, CardColor.red),
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.four, CardColor.red),
        Card(CardFace.three, CardColor.green),
        Card(CardFace.two, CardColor.blue),
      ];
      final selected = [
        Card(CardFace.six, CardColor.black),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.three, CardColor.red),
        Card(CardFace.two, CardColor.green),
      ];

      expect(selectionMatchesTurn(turnCards, selected), isTrue);
    });

    test('requires same suit for straight bombs', () {
      final straightBomb = [
        Card(CardFace.six, CardColor.red),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.four, CardColor.red),
        Card(CardFace.three, CardColor.red),
        Card(CardFace.two, CardColor.red),
      ];
      final mixedSelected = [
        Card(CardFace.six, CardColor.black),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.three, CardColor.red),
        Card(CardFace.two, CardColor.green),
      ];
      final sameSuitSelected = [
        Card(CardFace.six, CardColor.red),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.four, CardColor.red),
        Card(CardFace.three, CardColor.red),
        Card(CardFace.two, CardColor.red),
      ];

      expect(selectionMatchesTurn(straightBomb, mixedSelected), isFalse);
      expect(selectionMatchesTurn(straightBomb, sameSuitSelected), isTrue);
    });

    test('matches phoenix by face only', () {
      final turnCards = [
        Card(CardFace.six, CardColor.red),
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.four, CardColor.red),
        Card(CardFace.three, CardColor.green),
        const Card.phoenix(2.0),
      ];
      final selected = [
        Card(CardFace.six, CardColor.black),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.three, CardColor.red),
        Card(CardFace.phoenix, CardColor.special),
      ];

      expect(selectionMatchesTurn(turnCards, selected), isTrue);
    });
  });
}
