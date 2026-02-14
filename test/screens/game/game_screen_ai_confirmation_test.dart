import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/screens/game/game_screen.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import '../../utils/test_game_backend.dart';
import '../../utils/test_game_fixtures.dart';

void main() {
  testWidgets('shows pending opponent cards before confirmation', (
    tester,
  ) async {
    final backend = FakeGameBackend();

    await tester.pumpWidget(MaterialApp(home: GameScreen(backend: backend)));

    final pendingCards = [
      Card(CardFace.five, CardColor.red),
      Card(CardFace.five, CardColor.blue),
    ];

    backend.emit(
      buildPlayerSnapshot(
        pendingOpponentPlayerId: testOpponentLeftId,
        pendingOpponentCards: pendingCards,
        opponentAwaitingConfirmation: true,
      ),
    );

    await tester.pump();

    expect(find.text('No cards on table'), findsOneWidget);

    expect(backend.actions.whereType<ConfirmOpponentTurnAction>().length, 0);

    backend.emit(
      buildPlayerSnapshot(
        deck: DeckState(TichuTurn(TurnType.pair, pendingCards), CardFace.none),
        currentPlayerId: testHumanId,
      ),
    );

    await tester.pump();

    expect(find.text('No cards on table'), findsNothing);

    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('shows PASS for pending opponent pass', (tester) async {
    final backend = FakeGameBackend();

    await tester.pumpWidget(MaterialApp(home: GameScreen(backend: backend)));

    backend.emit(
      buildPlayerSnapshot(
        pendingOpponentPlayerId: testOpponentLeftId,
        pendingOpponentCards: const [],
        pendingOpponentPass: true,
        opponentAwaitingConfirmation: true,
      ),
    );

    await tester.pump();

    expect(find.text('Pass'), findsWidgets);

    await tester.pump(const Duration(milliseconds: 700));
  });
}
