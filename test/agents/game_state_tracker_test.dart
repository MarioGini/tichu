import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/game_state_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'ai_test_fixtures.dart';

void main() {
  group('GameStateTracker', () {
    test('detects all aces known and hasLastAce', () {
      final tracker = GameStateTracker();
      final snapshot = aiSnapshot(
        myHand: [
          Card(CardFace.ace, CardColor.red),
          Card(CardFace.ace, CardColor.blue),
          Card(CardFace.ace, CardColor.green),
          Card(CardFace.ace, CardColor.black),
        ],
      );

      tracker.update(snapshot, aiTestSelfId);

      expect(tracker.allAcesKnown, isTrue);
      expect(tracker.hasLastAce(snapshot.hands[aiTestSelfId]!), isTrue);
    });

    test('round change resets known cards', () {
      final tracker = GameStateTracker();
      tracker.update(
        aiSnapshot(
          myHand: [
            Card(CardFace.king, CardColor.red),
            Card(CardFace.king, CardColor.blue),
            Card(CardFace.king, CardColor.green),
            Card(CardFace.king, CardColor.black),
          ],
        ),
        aiTestSelfId,
      );
      expect(tracker.allKingsKnown, isTrue);

      tracker.update(
        aiSnapshot(myHand: aiDefaultHand(), roundNumber: 2),
        aiTestSelfId,
      );
      expect(tracker.allKingsKnown, isFalse);
    });
  });
}
