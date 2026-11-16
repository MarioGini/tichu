import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/screens/game/game_screen.dart';
import 'package:tichu/screens/game/widgets/schupf_panel.dart';
import 'package:tichu/widgets/card_widget.dart';

import '../../utils/test_game_fixtures.dart';
import '../../utils/test_game_match_service.dart';

/// Pixel 7 in the browser: portrait and landscape, with and without the
/// browser's address bar.
void main() {
  final fullHand = [
    for (final face in [
      CardFace.two,
      CardFace.three,
      CardFace.four,
      CardFace.five,
      CardFace.six,
      CardFace.seven,
      CardFace.eight,
      CardFace.nine,
      CardFace.ten,
      CardFace.jack,
      CardFace.queen,
      CardFace.king,
      CardFace.ace,
    ])
      Card(face, CardColor.red),
    Card(CardFace.dragon, CardColor.special),
  ];

  const sizes = [
    Size(412, 839),
    Size(412, 915),
    Size(863, 360),
    Size(915, 412),
  ];

  Future<FakeGameMatchService> pumpAt(
    final WidgetTester tester,
    final Size size,
  ) async {
    tester.view
      ..physicalSize = size * 2.625
      ..devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final backend = FakeGameMatchService();
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          matchService: backend,
          sessionHandle: backend.sessionHandle,
        ),
      ),
    );
    return backend;
  }

  for (final size in sizes) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('play phase fits on screen at $label', (final tester) async {
      final backend = await pumpAt(tester, size);
      backend.emit(
        buildPlayerSnapshot(
          currentPlayerId: testHumanId,
          hand: fullHand,
          canCallTichu: true,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final screen = Offset.zero & size;
      for (final element in find.byType(CardWidget).evaluate()) {
        final rect = tester.getRect(find.byWidget(element.widget));
        expect(screen.contains(rect.topLeft), isTrue, reason: '$rect');
        expect(rect.bottom, lessThanOrEqualTo(size.height + 0.5));
        expect(rect.height, greaterThanOrEqualTo(70), reason: 'card too small');
      }
      for (final text in ['PLAY', 'Pass', 'Tichu']) {
        final rect = tester.getRect(find.text(text));
        expect(rect.bottom, lessThanOrEqualTo(size.height), reason: text);
      }
    });

    testWidgets('busy play phase fits on screen at $label', (
      final tester,
    ) async {
      final backend = await pumpAt(tester, size);
      final trick = [
        for (final face in [CardFace.five, CardFace.six, CardFace.seven])
          Card(face, CardColor.blue),
        Card(CardFace.eight, CardColor.green),
        Card(CardFace.nine, CardColor.green),
      ];
      backend.emit(
        buildPlayerSnapshot(
          currentPlayerId: testHumanId,
          hand: fullHand,
          hasBombInHand: true,
          deck: DeckState(TichuTurn(TurnType.straight, trick), CardFace.none),
          lastPlayedBy: testOpponentLeftId,
          trickPoints: 25,
          activeWish: CardFace.king,
          pendingOpponentPlayerId: testOpponentPartnerId,
          pendingOpponentCards: [
            Card(CardFace.ten, CardColor.red),
            Card(CardFace.jack, CardColor.red),
            Card(CardFace.queen, CardColor.red),
            Card(CardFace.king, CardColor.red),
            Card(CardFace.ace, CardColor.red),
          ],
          opponentAwaitingConfirmation: true,
          scoreState: const ScoreState(
            roundNumber: 3,
            teamOneTotal: 340,
            teamTwoTotal: 285,
            teamOneRound: 0,
            teamTwoRound: 0,
            playerRoundPoints: {},
            roundComplete: false,
            targetScore: 1000,
            gameComplete: false,
            winningTeam: null,
            finishOrder: [],
            rounds: [],
            tichuCalls: {
              testHumanId: TichuCall.grandTichu,
              testOpponentLeftId: TichuCall.tichu,
            },
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('GRAND'), findsOneWidget);
      for (final element in find.byType(CardWidget).evaluate()) {
        final rect = tester.getRect(find.byWidget(element.widget));
        expect(rect.bottom, lessThanOrEqualTo(size.height + 0.5));
        expect(rect.right, lessThanOrEqualTo(size.width + 0.5));
      }
    });

    testWidgets('match end fits at $label', (final tester) async {
      final backend = await pumpAt(tester, size);
      backend.emit(
        buildPlayerSnapshot(
          currentPlayerId: testOpponentLeftId,
          hand: const [],
          scoreState: const ScoreState(
            roundNumber: 9,
            teamOneTotal: 1020,
            teamTwoTotal: 640,
            teamOneRound: 0,
            teamTwoRound: 0,
            playerRoundPoints: {},
            roundComplete: false,
            targetScore: 1000,
            gameComplete: true,
            winningTeam: 0,
            finishOrder: [testHumanId, testOpponentLeftId],
            rounds: [],
            tichuCalls: {testHumanId: TichuCall.tichu},
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Your team wins'), findsOneWidget);
      expect(find.text('PLAY'), findsNothing);
    });

    testWidgets('schupf phase fits on screen at $label', (final tester) async {
      final backend = await pumpAt(tester, size);
      backend.emit(
        buildPlayerSnapshot(
          phase: GamePhase.schupf,
          currentPlayerId: testHumanId,
          hand: fullHand,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final panel = tester.getRect(find.byType(SchupfPanel));
      expect(panel.bottom, lessThanOrEqualTo(size.height + 0.5));
      final schupf = tester.getRect(find.text('Schupf'));
      expect(schupf.bottom, lessThanOrEqualTo(size.height));
      for (final element in find.byType(CardWidget).evaluate()) {
        final rect = tester.getRect(find.byWidget(element.widget));
        expect(rect.bottom, lessThanOrEqualTo(size.height + 0.5));
      }
    });
  }
}
