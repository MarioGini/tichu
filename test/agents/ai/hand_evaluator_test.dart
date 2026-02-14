import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/ai/hand_evaluator.dart';
import 'package:tichu/game/turn/tichu_data.dart';

void main() {
  group('HandEvaluator.evaluate', () {
    test('empty hand scores 0', () {
      expect(HandEvaluator.evaluate([]), 0);
    });

    test('dragon alone gives high card score', () {
      final hand = [Card(CardFace.dragon, CardColor.special)];
      final score = HandEvaluator.evaluate(hand);
      expect(score, greaterThan(10));
    });

    test('phoenix alone gives decent score', () {
      final hand = [Card(CardFace.phoenix, CardColor.special)];
      final score = HandEvaluator.evaluate(hand);
      expect(score, greaterThan(5));
    });

    test('multiple aces score high', () {
      final hand = [
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.ace, CardColor.blue),
        Card(CardFace.ace, CardColor.green),
      ];
      final score = HandEvaluator.evaluate(hand);
      // 3 aces × 8 = 24, plus triplet bonus 4, etc.
      expect(score, greaterThan(25));
    });

    test('weak hand scores low', () {
      final hand = [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.three, CardColor.blue),
        Card(CardFace.four, CardColor.green),
        Card(CardFace.six, CardColor.black),
        Card(CardFace.eight, CardColor.red),
        Card(CardFace.ten, CardColor.blue),
        Card(CardFace.dog, CardColor.special),
        Card(CardFace.mahJong, CardColor.special),
      ];
      final score = HandEvaluator.evaluate(hand);
      expect(score, lessThan(30));
    });

    test('monster hand scores very high', () {
      final hand = [
        Card(CardFace.dragon, CardColor.special),
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.ace, CardColor.blue),
        Card(CardFace.ace, CardColor.green),
        Card(CardFace.ace, CardColor.black),
        Card(CardFace.king, CardColor.red),
        Card(CardFace.king, CardColor.blue),
      ];
      final score = HandEvaluator.evaluate(hand);
      // Dragon (15) + Phoenix (10) + 4 aces (32) + 2 kings (6) + bomb (15)
      // + pair (2) = 80+
      expect(score, greaterThanOrEqualTo(70));
    });

    test('hand with a straight scores connectivity bonus', () {
      // Connected hand: a 5-card straight + king + paired aces → high score
      final straightHand = [
        Card(CardFace.four, CardColor.red),
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.six, CardColor.green),
        Card(CardFace.seven, CardColor.black),
        Card(CardFace.eight, CardColor.red),
        Card(CardFace.king, CardColor.blue),
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.ace, CardColor.blue),
      ];

      // Disjointed hand: same high cards but no long sequence
      final disjointed = [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.six, CardColor.green),
        Card(CardFace.eight, CardColor.black),
        Card(CardFace.ten, CardColor.red),
        Card(CardFace.king, CardColor.blue),
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.ace, CardColor.blue),
      ];

      final straightScore = HandEvaluator.evaluate(straightHand);
      final disjointedScore = HandEvaluator.evaluate(disjointed);
      expect(straightScore, greaterThan(disjointedScore));
    });

    test('pairs and triplets increase score', () {
      final withPairs = [
        Card(CardFace.ten, CardColor.red),
        Card(CardFace.ten, CardColor.blue),
        Card(CardFace.jack, CardColor.green),
        Card(CardFace.jack, CardColor.black),
        Card(CardFace.five, CardColor.red),
      ];
      final noPairs = [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.six, CardColor.green),
        Card(CardFace.eight, CardColor.black),
        Card(CardFace.ten, CardColor.red),
      ];
      expect(
        HandEvaluator.evaluate(withPairs),
        greaterThan(HandEvaluator.evaluate(noPairs)),
      );
    });
  });

  group('HandEvaluator.shouldCallGrandTichu', () {
    test('declines with weak 8-card hand', () {
      final hand = [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.three, CardColor.blue),
        Card(CardFace.four, CardColor.green),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.six, CardColor.red),
        Card(CardFace.seven, CardColor.blue),
        Card(CardFace.eight, CardColor.green),
        Card(CardFace.dog, CardColor.special),
      ];
      expect(HandEvaluator.shouldCallGrandTichu(hand), false);
    });

    test('accepts with dragon + phoenix + multiple aces + bomb', () {
      final hand = [
        Card(CardFace.dragon, CardColor.special),
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.ace, CardColor.blue),
        Card(CardFace.ace, CardColor.green),
        Card(CardFace.ace, CardColor.black),
        Card(CardFace.king, CardColor.red),
        Card(CardFace.king, CardColor.blue),
      ];
      expect(HandEvaluator.shouldCallGrandTichu(hand), true);
    });
  });

  group('HandEvaluator.shouldCallTichu', () {
    test('declines with average hand', () {
      final hand = [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.three, CardColor.blue),
        Card(CardFace.four, CardColor.green),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.six, CardColor.red),
        Card(CardFace.seven, CardColor.blue),
        Card(CardFace.eight, CardColor.green),
        Card(CardFace.nine, CardColor.black),
        Card(CardFace.ten, CardColor.red),
        Card(CardFace.jack, CardColor.blue),
        Card(CardFace.queen, CardColor.green),
        Card(CardFace.king, CardColor.black),
        Card(CardFace.dog, CardColor.special),
        Card(CardFace.mahJong, CardColor.special),
      ];
      expect(HandEvaluator.shouldCallTichu(hand), false);
    });

    test('accepts with strong 14-card hand', () {
      final hand = [
        Card(CardFace.dragon, CardColor.special),
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.ace, CardColor.blue),
        Card(CardFace.ace, CardColor.green),
        Card(CardFace.king, CardColor.red),
        Card(CardFace.king, CardColor.blue),
        Card(CardFace.king, CardColor.green),
        Card(CardFace.queen, CardColor.red),
        Card(CardFace.queen, CardColor.blue),
        Card(CardFace.jack, CardColor.red),
        Card(CardFace.ten, CardColor.red),
        Card(CardFace.nine, CardColor.red),
        Card(CardFace.eight, CardColor.red),
      ];
      expect(HandEvaluator.shouldCallTichu(hand), true);
    });
  });

  group('HandEvaluator score ranges', () {
    test('score is always between 0 and 100', () {
      // Test with various hand sizes
      final hands = [
        <Card>[],
        [Card(CardFace.two, CardColor.red)],
        [
          Card(CardFace.dragon, CardColor.special),
          Card(CardFace.phoenix, CardColor.special),
          Card(CardFace.ace, CardColor.red),
          Card(CardFace.ace, CardColor.blue),
          Card(CardFace.ace, CardColor.green),
          Card(CardFace.ace, CardColor.black),
          Card(CardFace.king, CardColor.red),
          Card(CardFace.king, CardColor.blue),
          Card(CardFace.king, CardColor.green),
          Card(CardFace.king, CardColor.black),
          Card(CardFace.queen, CardColor.red),
          Card(CardFace.queen, CardColor.blue),
          Card(CardFace.queen, CardColor.green),
          Card(CardFace.queen, CardColor.black),
        ],
      ];

      for (final hand in hands) {
        final score = HandEvaluator.evaluate(hand);
        expect(score, greaterThanOrEqualTo(0));
        expect(score, lessThanOrEqualTo(100));
      }
    });
  });
}
