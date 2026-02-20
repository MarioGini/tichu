import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/tichu_call_strategy.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'ai_test_fixtures.dart';

void main() {
  const strategy = DefaultTichuCallStrategy();

  test('grand tichu always returns false', () async {
    final snapshot = aiSnapshot(
      myHand: [
        Card(CardFace.dragon, CardColor.special),
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.ace, CardColor.blue),
        Card(CardFace.ace, CardColor.green),
        Card(CardFace.ace, CardColor.black),
        Card(CardFace.king, CardColor.red),
        Card(CardFace.king, CardColor.blue),
      ],
    );

    expect(
      await strategy.shouldCallGrandTichu(snapshot, aiTestSelfId),
      isFalse,
    );
  });

  test('tichu follows paper index threshold (It >= 7)', () async {
    final belowThreshold = aiSnapshot(
      myHand: [
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.dog, CardColor.special),
        Card(CardFace.two, CardColor.blue),
        Card(CardFace.three, CardColor.green),
        Card(CardFace.four, CardColor.black),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.seven, CardColor.green),
        Card(CardFace.eight, CardColor.black),
        Card(CardFace.nine, CardColor.red),
        Card(CardFace.ten, CardColor.blue),
        Card(CardFace.jack, CardColor.green),
        Card(CardFace.queen, CardColor.black),
        Card(CardFace.king, CardColor.red),
      ],
    );

    final atOrAboveThreshold = aiSnapshot(
      myHand: [
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.ace, CardColor.blue),
        Card(CardFace.dragon, CardColor.special),
        Card(CardFace.king, CardColor.red),
        Card(CardFace.king, CardColor.blue),
        Card(CardFace.king, CardColor.green),
        Card(CardFace.king, CardColor.black),
        Card(CardFace.queen, CardColor.red),
        Card(CardFace.queen, CardColor.blue),
        Card(CardFace.jack, CardColor.green),
        Card(CardFace.jack, CardColor.black),
        Card(CardFace.ten, CardColor.red),
        Card(CardFace.ten, CardColor.blue),
        Card(CardFace.nine, CardColor.green),
      ],
    );

    expect(
      await strategy.shouldCallTichu(belowThreshold, aiTestSelfId),
      isFalse,
    );
    expect(
      await strategy.shouldCallTichu(atOrAboveThreshold, aiTestSelfId),
      isTrue,
    );
  });
}
