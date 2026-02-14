import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/bomb_timing_strategy.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'ai_test_fixtures.dart';

void main() {
  test(
    'DefaultBombTimingStrategy is conservative and never bombs by default',
    () {
      const strategy = DefaultBombTimingStrategy();
      final snapshot = aiSnapshot(myHand: aiDefaultHand());
      final deck = aiEmptyDeck();
      final bomb = TichuTurn(TurnType.bomb, [
        Card(CardFace.five, CardColor.red),
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.five, CardColor.black),
      ]);

      final shouldBomb = strategy.shouldBomb(
        snapshot,
        deck,
        bomb,
        aiDefaultHand(),
      );
      expect(shouldBomb, isFalse);
    },
  );
}
