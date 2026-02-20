import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/screens/game/game_screen.dart';
import 'package:tichu/widgets/opponent_display.dart';

import '../../utils/test_game_backend.dart';
import '../../utils/test_game_fixtures.dart';

void main() {
  testWidgets('places Opponent 3 on left and Opponent 1 on right', (
    tester,
  ) async {
    final backend = FakeGameBackend();

    await tester.pumpWidget(MaterialApp(home: GameScreen(backend: backend)));

    backend.emit(buildPlayerSnapshot(currentPlayerId: testOpponentLeftId));
    await tester.pump();

    final opponent3Center = tester.getCenter(find.text('Opponent 3'));
    final opponent1Center = tester.getCenter(find.text('Opponent 1'));

    expect(opponent3Center.dx, lessThan(opponent1Center.dx));
  });

  testWidgets('highlights Opponent 1 when it is the current player', (
    tester,
  ) async {
    final backend = FakeGameBackend();

    await tester.pumpWidget(MaterialApp(home: GameScreen(backend: backend)));

    backend.emit(buildPlayerSnapshot(currentPlayerId: testOpponentLeftId));
    await tester.pump();

    // Active player gets yellow border highlight; no 'Their turn' text needed.
    final opponent1Box = tester.widget<OpponentDisplay>(
      find.ancestor(
        of: find.text('Opponent 1'),
        matching: find.byType(OpponentDisplay),
      ),
    );
    final opponent3Box = tester.widget<OpponentDisplay>(
      find.ancestor(
        of: find.text('Opponent 3'),
        matching: find.byType(OpponentDisplay),
      ),
    );
    expect(opponent1Box.isActive, isTrue);
    expect(opponent3Box.isActive, isFalse);
  });

  testWidgets('highlights Opponent 3 when it is the current player', (
    tester,
  ) async {
    final backend = FakeGameBackend();

    await tester.pumpWidget(MaterialApp(home: GameScreen(backend: backend)));

    backend.emit(buildPlayerSnapshot(currentPlayerId: testOpponentRightId));
    await tester.pump();

    // Active player gets yellow border highlight; no 'Their turn' text needed.
    final opponent3Box = tester.widget<OpponentDisplay>(
      find.ancestor(
        of: find.text('Opponent 3'),
        matching: find.byType(OpponentDisplay),
      ),
    );
    final opponent1Box = tester.widget<OpponentDisplay>(
      find.ancestor(
        of: find.text('Opponent 1'),
        matching: find.byType(OpponentDisplay),
      ),
    );
    expect(opponent3Box.isActive, isTrue);
    expect(opponent1Box.isActive, isFalse);
  });
}
