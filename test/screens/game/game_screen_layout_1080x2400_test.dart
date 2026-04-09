import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/screens/game/game_screen.dart';
import 'package:tichu/screens/game/widgets/schupf_panel.dart';

import '../../utils/test_game_fixtures.dart';
import '../../utils/test_game_match_service.dart';

void main() {
  Future<void> pumpGame(
    final WidgetTester tester,
    final FakeGameMatchService backend,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          matchService: backend,
          sessionHandle: backend.sessionHandle,
        ),
      ),
    );
  }

  testWidgets('play phase has stable layout at 1080x2400', (
    final tester,
  ) async {
    final backend = FakeGameMatchService();
    await pumpGame(tester, backend);

    backend.emit(
      buildPlayerSnapshot(currentPlayerId: testHumanId, canCallTichu: true),
    );
    await tester.pump();

    expect(find.text('Pass'), findsOneWidget);
    expect(find.text('PLAY'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Tichu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'schupf phase keeps tichu button below schupf panel at 1080x2400',
    (final tester) async {
      final backend = FakeGameMatchService();
      await pumpGame(tester, backend);

      backend.emit(
        buildPlayerSnapshot(
          phase: GamePhase.schupf,
          currentPlayerId: testHumanId,
          hand: [
            Card(CardFace.two, CardColor.red),
            Card(CardFace.three, CardColor.blue),
            Card(CardFace.four, CardColor.green),
            Card(CardFace.five, CardColor.red),
            Card(CardFace.six, CardColor.blue),
            Card(CardFace.seven, CardColor.green),
            Card(CardFace.eight, CardColor.red),
            Card(CardFace.nine, CardColor.blue),
            Card(CardFace.ten, CardColor.green),
          ],
        ),
      );
      await tester.pump();

      expect(find.byType(SchupfPanel), findsOneWidget);
      expect(find.text('Schupf your cards'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Tichu'), findsOneWidget);

      final schupfRect = tester.getRect(find.byType(SchupfPanel));
      final tichuRect = tester.getRect(
        find.widgetWithText(OutlinedButton, 'Tichu'),
      );
      expect(tichuRect.top, greaterThanOrEqualTo(schupfRect.bottom - 0.1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('schupf receipt phase is stable at 1080x2400', (
    final tester,
  ) async {
    final backend = FakeGameMatchService();
    await pumpGame(tester, backend);

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
    expect(find.text('PLAY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
