import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/screens/game/game_screen.dart';

void main() {
  group('defaultWishFaceFromSchupf', () {
    test('uses the card schupfed to the right', () {
      final wish = defaultWishFaceFromSchupf(
        toLeft: Card(CardFace.three, CardColor.red),
        toPartner: Card(CardFace.jack, CardColor.blue),
        toRight: Card(CardFace.ace, CardColor.green),
      );

      expect(wish, CardFace.ace);
    });

    test('returns null when no right schupf card is available', () {
      final wish = defaultWishFaceFromSchupf(
        toLeft: Card(CardFace.king, CardColor.black),
        toPartner: Card(CardFace.ten, CardColor.red),
        toRight: null,
      );

      expect(wish, isNull);
    });
  });
}
