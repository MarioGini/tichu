import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/screens/game/game_screen.dart';

import '../../utils/test_game_backend.dart';
import '../../utils/test_game_fixtures.dart';

void main() {
  testWidgets('disables pass button when active wish can be fulfilled', (
    final tester,
  ) async {
    final backend = FakeGameBackend();

    await tester.pumpWidget(MaterialApp(home: GameScreen(backend: backend)));

    backend.emit(
      buildPlayerSnapshot(
        currentPlayerId: testHumanId,
        hand: [Card(CardFace.ace, CardColor.green)],
        deck: DeckState(
          TichuTurn(TurnType.single, [Card(CardFace.king, CardColor.red)]),
          CardFace.ace,
        ),
        activeWish: CardFace.ace,
      ),
    );

    await tester.pump();

    final passButtonFinder = find.widgetWithText(OutlinedButton, 'Pass');
    expect(passButtonFinder, findsOneWidget);

    final passButton = tester.widget<OutlinedButton>(passButtonFinder);
    expect(passButton.onPressed, isNull);
  });
}
