import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/screens/game/game_screen.dart';

import '../../utils/test_game_backend.dart';
import '../../utils/test_game_fixtures.dart';
import '../../utils/test_helpers.dart';

void main() {
  testWidgets('hides action bar during schupf phase', (tester) async {
    final oldHandler = FlutterError.onError;
    suppressOverflowErrors(oldHandler);
    addTearDown(() => FlutterError.onError = oldHandler);

    final backend = FakeGameBackend();
    await tester.pumpWidget(MaterialApp(home: GameScreen(backend: backend)));

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

  testWidgets('shows action bar during play phase', (tester) async {
    final backend = FakeGameBackend();
    await tester.pumpWidget(MaterialApp(home: GameScreen(backend: backend)));

    backend.emit(
      buildPlayerSnapshot(phase: GamePhase.play, currentPlayerId: testHumanId),
    );
    await tester.pump();

    expect(find.text('Bomb'), findsOneWidget);
    expect(find.text('Pass'), findsOneWidget);
    expect(find.text('PLAY'), findsOneWidget);
  });
}
