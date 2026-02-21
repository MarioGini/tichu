import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/screens/game/game_screen.dart';
import 'package:tichu/screens/shared/player_control.dart';

import '../../utils/test_game_backend.dart';
import '../../utils/test_game_fixtures.dart';

void main() {
  testWidgets(
    'defaults opponent delay to 1s for manual self when player-3 is AI',
    (final tester) async {
      final backend = FakeGameBackend();

      await tester.pumpWidget(MaterialApp(home: GameScreen(backend: backend)));
      await tester.pump();

      expect(backend.automatedActionDelay, const Duration(seconds: 1));
    },
  );

  testWidgets('defaults opponent delay to 1s for AI self', (
    final tester,
  ) async {
    final backend = FakeGameBackend();

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          backend: backend,
          playerControlModes: const {testHumanId: PlayerControlMode.ai},
        ),
      ),
    );
    await tester.pump();

    expect(backend.automatedActionDelay, const Duration(seconds: 1));
  });
}
