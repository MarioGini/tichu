import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/scoring/score_data.dart';
import 'package:tichu/game/turn/tichu_data.dart';

Card _card(CardFace face, CardColor color) => Card(face, color);

void main() {
  group('cardPoints map', () {
    test('contains all CardFace values except none', () {
      for (final face in CardFace.values) {
        if (face == CardFace.none) continue;
        expect(
          cardPoints.containsKey(face),
          isTrue,
          reason: '$face should be in cardPoints',
        );
      }
    });

    test('point values sum to 100 per full deck', () {
      // A full Tichu deck has 4 copies of each normal face (2–Ace)
      // plus 1 each of dragon, phoenix, mahJong, dog.
      var total = 0;

      for (final face in [
        CardFace.two,
        CardFace.three,
        CardFace.four,
        CardFace.five,
        CardFace.six,
        CardFace.seven,
        CardFace.eight,
        CardFace.nine,
        CardFace.ten,
        CardFace.jack,
        CardFace.queen,
        CardFace.king,
        CardFace.ace,
      ]) {
        total += (cardPoints[face] ?? 0) * 4;
      }

      total += cardPoints[CardFace.dragon] ?? 0;
      total += cardPoints[CardFace.phoenix] ?? 0;
      total += cardPoints[CardFace.mahJong] ?? 0;
      total += cardPoints[CardFace.dog] ?? 0;

      expect(total, 100);
    });
  });

  group('pointsForCard', () {
    test('five is worth 5', () {
      expect(pointsForCard(_card(CardFace.five, CardColor.red)), 5);
    });

    test('ten is worth 10', () {
      expect(pointsForCard(_card(CardFace.ten, CardColor.black)), 10);
    });

    test('king is worth 10', () {
      expect(pointsForCard(_card(CardFace.king, CardColor.green)), 10);
    });

    test('dragon is worth 25', () {
      expect(pointsForCard(_card(CardFace.dragon, CardColor.special)), 25);
    });

    test('phoenix is worth -25', () {
      expect(pointsForCard(_card(CardFace.phoenix, CardColor.special)), -25);
    });

    test('ace is worth 0', () {
      expect(pointsForCard(_card(CardFace.ace, CardColor.blue)), 0);
    });

    test('two is worth 0', () {
      expect(pointsForCard(_card(CardFace.two, CardColor.red)), 0);
    });

    test('dog is worth 0', () {
      expect(pointsForCard(_card(CardFace.dog, CardColor.special)), 0);
    });

    test('mahJong is worth 0', () {
      expect(pointsForCard(_card(CardFace.mahJong, CardColor.special)), 0);
    });
  });

  group('pointsForCards', () {
    test('empty list returns 0', () {
      expect(pointsForCards([]), 0);
    });

    test('single card returns its point value', () {
      expect(pointsForCards([_card(CardFace.ten, CardColor.red)]), 10);
    });

    test('sums positive values', () {
      final cards = [
        _card(CardFace.five, CardColor.red),
        _card(CardFace.ten, CardColor.blue),
        _card(CardFace.king, CardColor.green),
      ];
      expect(pointsForCards(cards), 25); // 5 + 10 + 10
    });

    test('phoenix subtracts 25', () {
      final cards = [
        _card(CardFace.ten, CardColor.red),
        _card(CardFace.phoenix, CardColor.special),
      ];
      expect(pointsForCards(cards), -15); // 10 + (-25)
    });

    test('dragon adds 25', () {
      final cards = [
        _card(CardFace.dragon, CardColor.special),
        _card(CardFace.five, CardColor.blue),
      ];
      expect(pointsForCards(cards), 30); // 25 + 5
    });

    test('all zero-point cards return 0', () {
      final cards = [
        _card(CardFace.two, CardColor.red),
        _card(CardFace.three, CardColor.blue),
        _card(CardFace.four, CardColor.green),
        _card(CardFace.ace, CardColor.black),
        _card(CardFace.dog, CardColor.special),
        _card(CardFace.mahJong, CardColor.special),
      ];
      expect(pointsForCards(cards), 0);
    });

    test('mixed hand with all scoring cards', () {
      final cards = [
        _card(CardFace.five, CardColor.red), // 5
        _card(CardFace.five, CardColor.blue), // 5
        _card(CardFace.ten, CardColor.green), // 10
        _card(CardFace.king, CardColor.black), // 10
        _card(CardFace.dragon, CardColor.special), // 25
        _card(CardFace.phoenix, CardColor.special), // -25
      ];
      expect(pointsForCards(cards), 30); // 5+5+10+10+25-25
    });
  });
}
