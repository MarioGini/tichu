import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/screens/game/game_screen.dart';

import '../../utils/test_game_backend.dart';
import '../../utils/test_game_fixtures.dart';

void main() {
  testWidgets('shows dragon recipients as left then right from player view', (
    tester,
  ) async {
    final backend = FakeGameBackend();

    await tester.pumpWidget(MaterialApp(home: GameScreen(backend: backend)));

    backend.emit(
      buildPlayerSnapshot(
        currentPlayerId: testHumanId,
        pendingDragonGiveBy: testHumanId,
        pendingDragonGiveTargets: const [
          testOpponentLeftId,
          testOpponentRightId,
        ],
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Who receives the dragon?'), findsOneWidget);

    final opponent3Button = find.widgetWithText(TextButton, 'Opponent 3');
    final opponent1Button = find.widgetWithText(TextButton, 'Opponent 1');
    expect(opponent3Button, findsOneWidget);
    expect(opponent1Button, findsOneWidget);

    final opponent3Dx = tester.getTopLeft(opponent3Button).dx;
    final opponent1Dx = tester.getTopLeft(opponent1Button).dx;
    expect(opponent3Dx, lessThan(opponent1Dx));

    await tester.tap(opponent3Button);
    await tester.pumpAndSettle();

    final giveDragonActions = backend.actions.whereType<GiveDragonAction>();
    expect(giveDragonActions, hasLength(1));
    expect(giveDragonActions.single.targetPlayerId, testOpponentRightId);
  });
}
