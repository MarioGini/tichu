import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/agents/tichu_call_strategy.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/scoring/score_tracker.dart';

import 'ai_test_fixtures.dart';

class _AlwaysCallTichuStrategy implements TichuCallStrategy {
  const _AlwaysCallTichuStrategy();

  @override
  Future<bool> shouldCallGrandTichu(
    final GameSnapshot snapshot,
    final String playerId,
  ) async => false;

  @override
  Future<bool> shouldCallTichu(final GameSnapshot snapshot, final String playerId) async =>
      true;
}

class _NeverCallTichuStrategy implements TichuCallStrategy {
  const _NeverCallTichuStrategy();

  @override
  Future<bool> shouldCallGrandTichu(
    final GameSnapshot snapshot,
    final String playerId,
  ) async => false;

  @override
  Future<bool> shouldCallTichu(final GameSnapshot snapshot, final String playerId) async =>
      false;
}

void main() {
  group('SmartAiAgent.selectAction', () {
    test(
      'returns CallTichuAction when call is available and strategy wants it',
      () async {
        final agent = SmartAiAgent(
          aiTestSelfId,
          tichuCallStrategy: const _AlwaysCallTichuStrategy(),
        );
        final snapshot = aiSnapshot(
          myHand: aiDefaultHand(),
          canCallTichuByPlayer: {aiTestSelfId: true},
        );

        final action = await agent.selectAction(snapshot);
        expect(action, isA<CallTichuAction>());
      },
    );

    test('falls back to turn selection when call is not available', () async {
      final agent = SmartAiAgent(
        aiTestSelfId,
        tichuCallStrategy: const _AlwaysCallTichuStrategy(),
      );
      final snapshot = aiSnapshot(
        myHand: aiDefaultHand(),
        canCallTichuByPlayer: {aiTestSelfId: false},
      );

      final action = await agent.selectAction(snapshot);
      expect(action, isNot(isA<CallTichuAction>()));
    });

    test('falls back to turn selection when strategy declines call', () async {
      final agent = SmartAiAgent(
        aiTestSelfId,
        tichuCallStrategy: const _NeverCallTichuStrategy(),
      );
      final snapshot = aiSnapshot(
        myHand: aiDefaultHand(),
        canCallTichuByPlayer: {aiTestSelfId: true},
      );

      final action = await agent.selectAction(snapshot);
      expect(action, isNot(isA<CallTichuAction>()));
    });

    test('does not call tichu when partner already called tichu', () async {
      final agent = SmartAiAgent(
        aiTestSelfId,
        tichuCallStrategy: const _AlwaysCallTichuStrategy(),
      );
      final snapshot = aiSnapshot(
        myHand: aiDefaultHand(),
        canCallTichuByPlayer: {aiTestSelfId: true},
        tichuCalls: {aiTestPartnerId: TichuCall.tichu},
      );

      final action = await agent.selectAction(snapshot);
      expect(action, isNot(isA<CallTichuAction>()));
    });

    test(
      'does not call tichu when partner already called grand tichu',
      () async {
        final agent = SmartAiAgent(
          aiTestSelfId,
          tichuCallStrategy: const _AlwaysCallTichuStrategy(),
        );
        final snapshot = aiSnapshot(
          myHand: aiDefaultHand(),
          canCallTichuByPlayer: {aiTestSelfId: true},
          tichuCalls: {aiTestPartnerId: TichuCall.grandTichu},
        );

        final action = await agent.selectAction(snapshot);
        expect(action, isNot(isA<CallTichuAction>()));
      },
    );
  });
}
