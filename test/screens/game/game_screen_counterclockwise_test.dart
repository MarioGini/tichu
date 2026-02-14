import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/screens/game/game_screen.dart';
import 'package:tichu/widgets/opponent_display.dart';

import '../../utils/test_game_backend.dart';
import '../../utils/test_game_fixtures.dart';

void main() {
  Finder opponentTile(String name) {
    return find.ancestor(
      of: find.text(name),
      matching: find.byType(OpponentDisplay),
    );
  }

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

    final opponent1Tile = opponentTile('Opponent 1');
    final opponent3Tile = opponentTile('Opponent 3');

    expect(
      find.descendant(of: opponent1Tile, matching: find.text('Their turn')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: opponent3Tile, matching: find.text('Their turn')),
      findsNothing,
    );
  });

  testWidgets('highlights Opponent 3 when it is the current player', (
    tester,
  ) async {
    final backend = FakeGameBackend();

    await tester.pumpWidget(MaterialApp(home: GameScreen(backend: backend)));

    backend.emit(buildPlayerSnapshot(currentPlayerId: testOpponentRightId));
    await tester.pump();

    final opponent1Tile = opponentTile('Opponent 1');
    final opponent3Tile = opponentTile('Opponent 3');

    expect(
      find.descendant(of: opponent3Tile, matching: find.text('Their turn')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: opponent1Tile, matching: find.text('Their turn')),
      findsNothing,
    );
  });

  testWidgets('hides turn labels while schupf receipts are pending', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('A RenderFlex overflowed')) {
        return;
      }
      previousOnError?.call(details);
    };
    addTearDown(() {
      FlutterError.onError = previousOnError;
    });

    final backend = FakeGameBackend();

    await tester.pumpWidget(MaterialApp(home: GameScreen(backend: backend)));

    backend.emit(
      buildPlayerSnapshot(
        currentPlayerId: testOpponentLeftId,
        schupfReceipts: [
          SchupfReceipt(
            card: Card(CardFace.five, CardColor.red),
            fromPlayerId: testOpponentLeftId,
            direction: SchupfDirection.left,
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('Their turn'), findsNothing);

    backend.emit(buildPlayerSnapshot(currentPlayerId: testOpponentLeftId));
    await tester.pump();

    expect(find.text('Their turn'), findsOneWidget);
  });

  testWidgets('hides turn labels while opponent action is pending confirm', (
    tester,
  ) async {
    final backend = FakeGameBackend();

    await tester.pumpWidget(MaterialApp(home: GameScreen(backend: backend)));

    backend.emit(
      buildPlayerSnapshot(
        currentPlayerId: testOpponentPartnerId,
        pendingOpponentPlayerId: testOpponentLeftId,
        pendingOpponentCards: [Card(CardFace.king, CardColor.red)],
        opponentAwaitingConfirmation: true,
      ),
    );
    await tester.pump();

    expect(find.text('Their turn'), findsNothing);

    backend.emit(buildPlayerSnapshot(currentPlayerId: testOpponentPartnerId));
    await tester.pump();

    expect(find.text('Their turn'), findsOneWidget);
  });
}
