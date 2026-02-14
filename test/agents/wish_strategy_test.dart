import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/wish_strategy.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'ai_test_fixtures.dart';

void main() {
  const strategy = DefaultWishStrategy();

  group('DefaultWishStrategy', () {
    test('uses preferred face when wishable', () {
      final wish = strategy.selectWish(
        aiSnapshot(myHand: aiDefaultHand()),
        aiDefaultHand(),
        aiEmptyDeck(),
        preferredFace: CardFace.seven,
      );

      expect(wish, CardFace.seven);
    });

    test('falls back to highest missing card from A,K,Q,J,10', () {
      final hand = [
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.king, CardColor.blue),
      ];

      final wish = strategy.selectWish(
        aiSnapshot(myHand: hand),
        hand,
        aiEmptyDeck(),
      );

      expect(wish, CardFace.queen);
    });

    test('returns none if all high targets already in hand', () {
      final hand = [
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.king, CardColor.blue),
        Card(CardFace.queen, CardColor.green),
        Card(CardFace.jack, CardColor.black),
        Card(CardFace.ten, CardColor.red),
      ];

      final wish = strategy.selectWish(
        aiSnapshot(myHand: hand),
        hand,
        aiEmptyDeck(),
      );

      expect(wish, CardFace.none);
    });

    test('accepts every numeric/face preferred wish', () {
      const wishableFaces = [
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
      ];

      for (final face in wishableFaces) {
        final wish = strategy.selectWish(
          aiSnapshot(myHand: aiDefaultHand()),
          aiDefaultHand(),
          aiEmptyDeck(),
          preferredFace: face,
        );
        expect(wish, face);
      }
    });

    test('ignores non-wishable preferred faces and falls back', () {
      const nonWishableFaces = [
        CardFace.none,
        CardFace.mahJong,
        CardFace.dragon,
        CardFace.phoenix,
        CardFace.dog,
      ];

      final hand = [Card(CardFace.king, CardColor.red)];

      for (final face in nonWishableFaces) {
        final wish = strategy.selectWish(
          aiSnapshot(myHand: hand),
          hand,
          aiEmptyDeck(),
          preferredFace: face,
        );
        expect(wish, CardFace.ace);
      }
    });
  });
}
