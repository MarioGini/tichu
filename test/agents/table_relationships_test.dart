import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/table_relationships.dart';

import 'ai_test_fixtures.dart';

void main() {
  group('TableRelationships', () {
    test('resolves partner and opponents by seat parity', () {
      final table = TableRelationships(
        aiSnapshot(myHand: aiDefaultHand()),
        aiTestSelfId,
      );

      expect(table.partnerId, aiTestPartnerId);
      expect(table.isPartner(aiTestPartnerId), isTrue);
      expect(table.isOpponent(aiTestLeftId), isTrue);
      expect(table.isOpponent(aiTestRightId), isTrue);
      expect(table.isOpponent(aiTestSelfId), isFalse);
    });

    test('left/right seats and players match table orientation', () {
      final table = TableRelationships(
        aiSnapshot(myHand: aiDefaultHand()),
        aiTestSelfId,
      );

      expect(table.leftSeat(), 1);
      expect(table.rightSeat(), 3);
      expect(table.playerBySeat(table.leftSeat()).id, aiTestLeftId);
      expect(table.playerBySeat(table.rightSeat()).id, aiTestRightId);
    });
  });
}
