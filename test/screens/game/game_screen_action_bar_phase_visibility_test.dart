import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/screens/game/game_screen.dart';

import '../../utils/test_game_fixtures.dart';
import '../../utils/test_game_match_service.dart';
import '../../utils/test_helpers.dart';

void main() {
  testWidgets('hides action bar during schupf phase', (final tester) async {
    final oldHandler = FlutterError.onError;
    suppressOverflowErrors(oldHandler);
    addTearDown(() => FlutterError.onError = oldHandler);

    final backend = FakeGameMatchService();
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          matchService: backend,
          sessionHandle: backend.sessionHandle,
        ),
      ),
    );

    backend.emit(
      buildPlayerSnapshot(
        phase: GamePhase.schupf,
        currentPlayerId: testHumanId,
      ),
    );
    await tester.pump();

    expect(find.text('Bomb'), findsNothing);
    expect(find.text('Pass'), findsNothing);
    expect(find.text('PLAY'), findsNothing);
  });

  testWidgets('shows action bar during play phase', (final tester) async {
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
    await tester.pump();

    expect(find.text('Bomb'), findsNothing);
    expect(find.text('Pass'), findsOneWidget);
    expect(find.text('PLAY'), findsOneWidget);
  });
}
