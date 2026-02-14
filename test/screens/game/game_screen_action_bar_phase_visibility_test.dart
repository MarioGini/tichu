import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/screens/game/game_screen.dart';

import '../../utils/test_game_backend.dart';
import '../../utils/test_game_fixtures.dart';

void main() {
  testWidgets('hides bomb/pass/PLAY during schupf and shows them in play', (
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
        phase: GamePhase.schupf,
        currentPlayerId: testHumanId,
      ),
    );
    await tester.pump();

    expect(find.text('Bomb'), findsNothing);
    expect(find.text('Pass'), findsNothing);
    expect(find.text('PLAY'), findsNothing);
    expect(find.textContaining('pts'), findsNothing);

    backend.emit(
      buildPlayerSnapshot(
        phase: GamePhase.play,
        currentPlayerId: testHumanId,
        schupfCompletedPlayers: const <String>[testHumanId],
        schupfReceipts: [
          SchupfReceipt(
            fromPlayerId: testOpponentLeftId,
            direction: SchupfDirection.left,
            card: Card(CardFace.five, CardColor.red),
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('Schupf received'), findsOneWidget);
    expect(find.text('Bomb'), findsNothing);
    expect(find.text('Pass'), findsNothing);
    expect(find.text('PLAY'), findsOneWidget);

    backend.emit(
      buildPlayerSnapshot(phase: GamePhase.play, currentPlayerId: testHumanId),
    );
    await tester.pump();

    expect(find.text('Bomb'), findsOneWidget);
    expect(find.text('Pass'), findsOneWidget);
    expect(find.text('PLAY'), findsOneWidget);
    expect(find.textContaining('pts'), findsWidgets);
  });
}
