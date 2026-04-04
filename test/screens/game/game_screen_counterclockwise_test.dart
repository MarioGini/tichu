import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/screens/game/game_screen.dart';
import 'package:tichu/widgets/opponent_display.dart';

import '../../utils/test_game_backend.dart';
import '../../utils/test_game_fixtures.dart';

void main() {
  testWidgets('places Opponent 3 on left and Opponent 1 on right', (
    final tester,
  ) async {
    final backend = FakeGameBackend();

    await tester.pumpWidget(MaterialApp(home: GameScreen(backend: backend)));
    await tester.pump();

    backend.emit(buildPlayerSnapshot(currentPlayerId: testOpponentLeftId));
    await tester.pumpAndSettle();

    final opponent3Center = tester.getCenter(find.text('Opponent 3'));
    final opponent1Center = tester.getCenter(find.text('Opponent 1'));

    expect(opponent3Center.dx, lessThan(opponent1Center.dx));
  });

  testWidgets('highlights only the current player', (final tester) async {
    final backend = FakeGameBackend();

    await tester.pumpWidget(MaterialApp(home: GameScreen(backend: backend)));
    await tester.pump();

    OpponentDisplay opponentByName(final String name) =>
        tester.widget<OpponentDisplay>(
          find.ancestor(
            of: find.text(name),
            matching: find.byType(OpponentDisplay),
          ),
        );

    // Opponent 1 is current → only Opponent 1 highlighted.
    backend.emit(buildPlayerSnapshot(currentPlayerId: testOpponentLeftId));
    await tester.pumpAndSettle();
    expect(opponentByName('Opponent 1').isActive, isTrue);
    expect(opponentByName('Opponent 3').isActive, isFalse);

    // Opponent 3 is current → only Opponent 3 highlighted.
    backend.emit(buildPlayerSnapshot(currentPlayerId: testOpponentRightId));
    await tester.pumpAndSettle();
    expect(opponentByName('Opponent 3').isActive, isTrue);
    expect(opponentByName('Opponent 1').isActive, isFalse);
  });
}
