import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/screens/game/widgets/options_dialog.dart';
import 'package:tichu/screens/game/game_screen.dart';

import '../../utils/test_game_match_service.dart';
import '../../utils/test_game_fixtures.dart';

void main() {
  testWidgets(
    'options dialog updates automated action delay through match service',
    (final tester) async {
      final backend = FakeGameMatchService();

      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            matchService: backend,
            sessionHandle: backend.sessionHandle,
          ),
        ),
      );
      backend.emit(buildPlayerSnapshot(currentPlayerId: testHumanId));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      expect(find.byType(OptionsDialog), findsOneWidget);

      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged?.call(4);
      await tester.pump();

      expect(backend.automatedActionDelay, const Duration(seconds: 4));
    },
  );
}
