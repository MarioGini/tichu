import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/screens/game/game_screen.dart';
import 'package:tichu/widgets/card_widget.dart';

import '../../utils/test_game_backend.dart';
import '../../utils/test_game_fixtures.dart';
import '../../utils/test_helpers.dart';

void main() {
  testWidgets('quick schupf assign fills left then partner then right', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final previousOnError = FlutterError.onError;
    suppressOverflowErrors(previousOnError);
    addTearDown(() => FlutterError.onError = previousOnError);

    final backend = FakeGameBackend();

    await tester.pumpWidget(MaterialApp(home: GameScreen(backend: backend)));

    final hand = [
      Card(CardFace.four, CardColor.red),
      Card(CardFace.three, CardColor.blue),
      Card(CardFace.two, CardColor.green),
    ];

    backend.emit(
      buildPlayerSnapshot(
        hand: hand,
        currentPlayerId: testHumanId,
        phase: GamePhase.schupf,
      ),
    );

    await tester.pump();

    Future<void> quickAssignFirstAvailable() async {
      final firstDraggable = find.byType(Draggable<Card>).first;
      final center = tester.getCenter(firstDraggable);
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 120));
    }

    await quickAssignFirstAvailable();
    await quickAssignFirstAvailable();
    await quickAssignFirstAvailable();

    Finder cardFinder(Card card) {
      return find.byWidgetPredicate((widget) {
        return widget is CardWidget && widget.card == card;
      });
    }

    final firstCenter = tester.getCenter(cardFinder(hand[0]));
    final secondCenter = tester.getCenter(cardFinder(hand[1]));
    final thirdCenter = tester.getCenter(cardFinder(hand[2]));

    expect(firstCenter.dx, lessThan(secondCenter.dx));
    expect(secondCenter.dx, lessThan(thirdCenter.dx));
  });
}
