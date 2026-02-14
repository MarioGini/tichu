import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/screens/game/game_screen.dart';

import '../../utils/test_game_backend.dart';
import '../../utils/test_game_fixtures.dart';

void main() {
  testWidgets('shows and enables Tichu while eligible even off-turn', (
    tester,
  ) async {
    final backend = FakeGameBackend();

    await tester.pumpWidget(MaterialApp(home: GameScreen(backend: backend)));

    backend.emit(
      buildPlayerSnapshot(
        currentPlayerId: testOpponentLeftId,
        canCallTichu: true,
      ),
    );
    await tester.pump();

    final tichuButtonFinder = find.widgetWithText(OutlinedButton, 'Tichu');
    expect(tichuButtonFinder, findsOneWidget);

    final tichuButton = tester.widget<OutlinedButton>(tichuButtonFinder);
    expect(tichuButton.onPressed, isNotNull);

    await tester.tap(tichuButtonFinder);
    await tester.pump();

    expect(backend.actions.whereType<CallTichuAction>(), hasLength(1));
  });
}
