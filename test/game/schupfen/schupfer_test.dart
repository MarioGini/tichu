import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/schupfen/schupfer.dart';
import 'package:tichu/game/turn/tichu_data.dart';

void main() {
  group('SchupfSelection', () {
    test('stores cards received from each direction', () {
      final fromLeft = Card(CardFace.two, CardColor.red);
      final fromPartner = Card(CardFace.king, CardColor.blue);
      final fromRight = Card(CardFace.ace, CardColor.green);

      final selection = SchupfSelection(fromLeft, fromPartner, fromRight);

      expect(selection.fromLeft, fromLeft);
      expect(selection.fromPartner, fromPartner);
      expect(selection.fromRight, fromRight);
    });

    test('accepts special cards', () {
      final fromLeft = Card(CardFace.phoenix, CardColor.special);
      final fromPartner = Card(CardFace.dragon, CardColor.special);
      final fromRight = Card(CardFace.dog, CardColor.special);

      final selection = SchupfSelection(fromLeft, fromPartner, fromRight);

      expect(selection.fromLeft.face, CardFace.phoenix);
      expect(selection.fromPartner.face, CardFace.dragon);
      expect(selection.fromRight.face, CardFace.dog);
    });
  });

  group('SchupfSend', () {
    test('stores cards sent to each direction', () {
      final toLeft = Card(CardFace.three, CardColor.black);
      final toPartner = Card(CardFace.queen, CardColor.green);
      final toRight = Card(CardFace.seven, CardColor.red);

      final send = SchupfSend(toLeft, toPartner, toRight);

      expect(send.toLeft, toLeft);
      expect(send.toPartner, toPartner);
      expect(send.toRight, toRight);
    });

    test('each field is independent', () {
      final card = Card(CardFace.five, CardColor.blue);
      final send = SchupfSend(card, card, card);

      // All three hold the same card but are distinct fields.
      expect(send.toLeft, card);
      expect(send.toPartner, card);
      expect(send.toRight, card);
    });
  });
}
