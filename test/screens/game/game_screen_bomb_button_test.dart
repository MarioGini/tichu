import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/screens/game/game_screen.dart';

import '../../utils/test_game_backend.dart';
import '../../utils/test_game_fixtures.dart';

void main() {
  testWidgets('enables bomb button when hand contains bomb', (
    final tester,
  ) async {
    final backend = FakeGameBackend();

    await tester.pumpWidget(MaterialApp(home: GameScreen(backend: backend)));

    final bombHand = [
      Card(CardFace.five, CardColor.red),
      Card(CardFace.five, CardColor.blue),
      Card(CardFace.five, CardColor.green),
      Card(CardFace.five, CardColor.black),
      Card(CardFace.two, CardColor.red),
    ];

    backend.emit(
      buildPlayerSnapshot(
        hand: bombHand,
        currentPlayerId: testOpponentLeftId,
        hasBombInHand: true,
        canBomb: true,
      ),
    );

    await tester.pump();

    final bombButtonFinder = find.widgetWithText(OutlinedButton, 'Bomb');
    expect(bombButtonFinder, findsOneWidget);

    final bombButton = tester.widget<OutlinedButton>(bombButtonFinder);
    expect(bombButton.onPressed, isNotNull);
  });
}
