import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/agents/ai/tichu_call_strategy.dart';
import 'package:tichu/agents/opponents/default_opponent_agent.dart';
import 'package:tichu/agents/opponents/opponent_agent.dart';

import '../ai/ai_test_fixtures.dart';

class _AlwaysCallTichuStrategy implements TichuCallStrategy {
  const _AlwaysCallTichuStrategy();

  @override
  Future<bool> shouldCallGrandTichu(
    GameSnapshot snapshot,
    String playerId,
  ) async => false;

  @override
  Future<bool> shouldCallTichu(GameSnapshot snapshot, String playerId) async =>
      true;
}

class _NeverCallTichuStrategy implements TichuCallStrategy {
  const _NeverCallTichuStrategy();

  @override
  Future<bool> shouldCallGrandTichu(
    GameSnapshot snapshot,
    String playerId,
  ) async => false;

  @override
  Future<bool> shouldCallTichu(GameSnapshot snapshot, String playerId) async =>
      false;
}

void main() {
  group('DefaultOpponentAgent.selectAction', () {
    test(
      'returns CallTichuAction when call is available and strategy wants it',
      () async {
        final agent = DefaultOpponentAgent(
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
      final agent = DefaultOpponentAgent(
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
      final agent = DefaultOpponentAgent(
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
  });
}
