import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/screens/game/game_screen.dart';

import '../../utils/test_game_backend.dart';
import '../../utils/test_game_fixtures.dart';

void main() {
  testWidgets('match round requires continue before showing scoreboard', (
    tester,
  ) async {
    final backend = FakeGameBackend();

    await tester.pumpWidget(MaterialApp(home: GameScreen(backend: backend)));

    const scoreState = ScoreState(
      roundNumber: 1,
      teamOneTotal: 200,
      teamTwoTotal: 0,
      teamOneRound: 200,
      teamTwoRound: 0,
      playerRoundPoints: {
        testHumanId: 100,
        testOpponentPartnerId: 100,
        testOpponentLeftId: 0,
        testOpponentRightId: 0,
      },
      roundComplete: true,
      targetScore: 1000,
      gameComplete: false,
      winningTeam: null,
      finishOrder: [
        testHumanId,
        testOpponentPartnerId,
        testOpponentLeftId,
        testOpponentRightId,
      ],
      rounds: [
        RoundScore(
          roundNumber: 1,
          teamOnePoints: 200,
          teamTwoPoints: 0,
          teamOneCardPoints: 0,
          teamTwoCardPoints: 0,
          teamOneBonusPoints: 200,
          teamTwoBonusPoints: 0,
          finishOrder: [
            testHumanId,
            testOpponentPartnerId,
            testOpponentLeftId,
            testOpponentRightId,
          ],
          roundEndType: RoundEndType.match,
        ),
      ],
      tichuCalls: {},
    );

    backend.emit(
      buildPlayerSnapshot(
        phase: GamePhase.play,
        currentPlayerId: testOpponentLeftId,
        scoreState: scoreState,
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Round 1 complete'), findsNothing);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Round 1 complete'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
  });
}
