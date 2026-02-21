import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/screens/game/game_screen.dart';
import 'package:tichu/screens/shared/player_control.dart';
import 'package:tichu/widgets/card_widget.dart';
import 'package:tichu/widgets/hand_display.dart';

import '../../utils/test_game_backend.dart';
import '../../utils/test_game_fixtures.dart';
import '../../utils/test_helpers.dart';

void main() {
  testWidgets('keeps self turn indicator visible in AI self mode', (
    final tester,
  ) async {
    final backend = FakeGameBackend();

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          backend: backend,
          playerControlModes: const {testHumanId: PlayerControlMode.ai},
        ),
      ),
    );

    backend.emit(buildPlayerSnapshot(currentPlayerId: testHumanId));
    await tester.pump();

    final handDisplay = tester.widget<HandDisplay>(find.byType(HandDisplay));
    expect(handDisplay.isActive, isTrue);
  });

  testWidgets('keeps self turn indicator when AI self pending move is staged', (
    final tester,
  ) async {
    final backend = FakeGameBackend();

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          backend: backend,
          playerControlModes: const {testHumanId: PlayerControlMode.ai},
        ),
      ),
    );

    backend.emit(
      buildPlayerSnapshot(
        currentPlayerId: testHumanId,
        pendingOpponentPlayerId: testHumanId,
        pendingOpponentCards: [Card(CardFace.ace, CardColor.green)],
      ),
    );
    await tester.pump();

    final handDisplay = tester.widget<HandDisplay>(find.byType(HandDisplay));
    expect(handDisplay.isActive, isTrue);
  });

  testWidgets('shows AI self pending play cards as selected in hand', (
    final tester,
  ) async {
    final backend = FakeGameBackend();
    final ace = Card(CardFace.ace, CardColor.green);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          backend: backend,
          playerControlModes: const {testHumanId: PlayerControlMode.ai},
        ),
      ),
    );

    backend.emit(
      buildPlayerSnapshot(
        currentPlayerId: testHumanId,
        hand: [
          Card(CardFace.two, CardColor.red),
          ace,
          Card(CardFace.five, CardColor.blue),
        ],
        pendingOpponentPlayerId: testHumanId,
        pendingOpponentCards: [ace],
        opponentAwaitingConfirmation: true,
      ),
    );
    await tester.pump();

    final handDisplay = tester.widget<HandDisplay>(find.byType(HandDisplay));
    expect(handDisplay.selectedIndexes, hasLength(1));

    final selectedCard = handDisplay.cards[handDisplay.selectedIndexes.first];
    expect(selectedCard, ace);

    backend.emit(buildPlayerSnapshot(currentPlayerId: testHumanId));
    await tester.pump();

    final clearedHandDisplay = tester.widget<HandDisplay>(
      find.byType(HandDisplay),
    );
    expect(clearedHandDisplay.selectedIndexes, isEmpty);
  });

  testWidgets('shows AI self schupf cards in schupf target slots', (
    final tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final previousOnError = FlutterError.onError;
    suppressOverflowErrors(previousOnError);
    addTearDown(() => FlutterError.onError = previousOnError);

    final backend = FakeGameBackend();
    final toLeft = Card(CardFace.ace, CardColor.green);
    final toPartner = Card(CardFace.king, CardColor.red);
    final toRight = Card(CardFace.queen, CardColor.blue);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          backend: backend,
          playerControlModes: const {testHumanId: PlayerControlMode.ai},
        ),
      ),
    );

    backend.emit(
      buildPlayerSnapshot(
        phase: GamePhase.schupf,
        currentPlayerId: testHumanId,
        hand: [
          toLeft,
          toPartner,
          toRight,
          Card(CardFace.five, CardColor.black),
        ],
        schupfCompletedPlayers: const <String>[],
        pendingOpponentPlayerId: testHumanId,
        pendingOpponentCards: [toLeft, toPartner, toRight],
      ),
    );
    await tester.pump();

    expect(find.text('Schupf your cards'), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline), findsNothing);

    expect(
      find.byWidgetPredicate(
        (final widget) => widget is CardWidget && widget.card == toLeft,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (final widget) => widget is CardWidget && widget.card == toPartner,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (final widget) => widget is CardWidget && widget.card == toRight,
      ),
      findsOneWidget,
    );
  });
}
