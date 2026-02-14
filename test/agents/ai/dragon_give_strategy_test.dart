import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/ai/dragon_give_strategy.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'ai_test_fixtures.dart';

void main() {
  const strategy = DefaultDragonGiveStrategy();

  group('DefaultDragonGiveStrategy', () {
    test('avoids left opponent who called tichu', () {
      final snapshot = aiSnapshot(
        myHand: [Card(CardFace.dragon, CardColor.special)],
        tichuCalls: {aiTestLeftId: TichuCall.tichu},
      );

      expect(strategy.selectDragonGive(snapshot, aiTestSelfId), 3);
    });

    test('gives to opponent with more cards when no tichu asymmetry', () {
      final snapshot = aiSnapshot(
        myHand: [Card(CardFace.dragon, CardColor.special)],
        otherHands: {
          aiTestLeftId: List.generate(
            9,
            (_) => Card(CardFace.two, CardColor.red),
          ),
          aiTestPartnerId: aiDefaultHand(),
          aiTestRightId: List.generate(
            3,
            (_) => Card(CardFace.three, CardColor.blue),
          ),
        },
      );

      expect(strategy.selectDragonGive(snapshot, aiTestSelfId), 1);
    });
  });
}
