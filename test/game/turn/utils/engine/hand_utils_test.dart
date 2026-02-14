import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/engine/hand_utils.dart';

Card _card(CardFace face, CardColor color) => Card(face, color);

void main() {
  group('handContainsAll', () {
    test('returns true when all cards are present including duplicates', () {
      final hand = [
        _card(CardFace.five, CardColor.red),
        _card(CardFace.five, CardColor.blue),
        _card(CardFace.ten, CardColor.green),
      ];

      expect(
        handContainsAll(hand, [
          _card(CardFace.five, CardColor.red),
          _card(CardFace.five, CardColor.blue),
        ]),
        isTrue,
      );
    });

    test('matches phoenix by face regardless of value', () {
      final hand = [
        const Card.phoenix(1.5),
        _card(CardFace.ten, CardColor.red),
      ];

      expect(handContainsAll(hand, [const Card.phoenix(6.5)]), isTrue);
    });

    test('returns false when requested card is missing', () {
      final hand = [_card(CardFace.five, CardColor.red)];

      expect(
        handContainsAll(hand, [_card(CardFace.five, CardColor.blue)]),
        isFalse,
      );
    });
  });

  group('removeCardsFromHand', () {
    test('removes matching cards and keeps non-matching cards', () {
      final hand = [
        _card(CardFace.five, CardColor.red),
        _card(CardFace.five, CardColor.blue),
        _card(CardFace.ten, CardColor.green),
      ];

      removeCardsFromHand(hand, [_card(CardFace.five, CardColor.red)]);

      expect(hand, [
        _card(CardFace.five, CardColor.blue),
        _card(CardFace.ten, CardColor.green),
      ]);
    });

    test('removes phoenix by face match', () {
      final hand = [
        const Card.phoenix(1.5),
        _card(CardFace.two, CardColor.red),
      ];

      removeCardsFromHand(hand, [const Card.phoenix(9.5)]);

      expect(hand, [_card(CardFace.two, CardColor.red)]);
    });
  });

  group('fallbackSchupf', () {
    test('throws when fewer than three cards are available', () {
      expect(
        () => fallbackSchupf([_card(CardFace.two, CardColor.red)]),
        throwsStateError,
      );
    });

    test('returns the three lowest value cards', () {
      final hand = [
        _card(CardFace.king, CardColor.red),
        _card(CardFace.two, CardColor.red),
        _card(CardFace.five, CardColor.blue),
        _card(CardFace.three, CardColor.green),
      ];

      final (toLeft, toPartner, toRight) = fallbackSchupf(hand);
      expect(
        [toLeft.face, toPartner.face, toRight.face],
        [CardFace.two, CardFace.three, CardFace.five],
      );
    });
  });
}
