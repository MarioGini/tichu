import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/screens/game/game_screen.dart';

import '../../utils/test_game_backend.dart';
import '../../utils/test_game_fixtures.dart';
import '../../utils/test_helpers.dart';

void main() {
  testWidgets('PLAY on schupf receipts hides panel immediately', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final previousOnError = FlutterError.onError;
    suppressOverflowErrors(previousOnError);
    addTearDown(() => FlutterError.onError = previousOnError);

    final backend = FakeGameBackend();

    await tester.pumpWidget(MaterialApp(home: GameScreen(backend: backend)));

    backend.emit(
      buildPlayerSnapshot(
        phase: GamePhase.schupf,
        currentPlayerId: testOpponentLeftId,
        schupfCompletedPlayers: const <String>[testHumanId],
        schupfReceipts: [
          SchupfReceipt(
            fromPlayerId: testOpponentLeftId,
            direction: SchupfDirection.left,
            card: Card(CardFace.five, CardColor.red),
          ),
          SchupfReceipt(
            fromPlayerId: testOpponentPartnerId,
            direction: SchupfDirection.partner,
            card: Card(CardFace.six, CardColor.blue),
          ),
          SchupfReceipt(
            fromPlayerId: testOpponentRightId,
            direction: SchupfDirection.right,
            card: Card(CardFace.seven, CardColor.green),
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('Schupf received'), findsOneWidget);
    expect(find.text('Bomb'), findsNothing);
    expect(find.text('Pass'), findsNothing);
    expect(find.text('PLAY'), findsOneWidget);

    final playButton = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('PLAY'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    playButton.onPressed!.call();
    await tester.pump();

    expect(find.text('Schupf received'), findsNothing);
    expect(find.text('Accepting…'), findsNothing);
  });
}
