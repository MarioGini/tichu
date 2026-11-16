import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/screens/game/round_summary_screen.dart';
import 'package:tichu/screens/home/home_screen.dart';

void main() {
  for (final size in const [
    Size(412, 839),
    Size(863, 360),
    Size(915, 412),
    Size(600, 360),
    Size(1280, 800),
  ]) {
    testWidgets('home screen fits at ${size.width.toInt()}x'
        '${size.height.toInt()}', (final tester) async {
      tester.view
        ..physicalSize = size * 2
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pump();

      expect(tester.takeException(), isNull);
      final play = find.text('Play vs AI');
      expect(play, findsOneWidget);
      final rect = tester.getRect(play);
      expect(rect.bottom, lessThanOrEqualTo(size.height));
      expect(rect.right, lessThanOrEqualTo(size.width));

      // Stop the periodic lobby refresh.
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final size in const [Size(863, 360), Size(412, 839)]) {
    testWidgets('round summary with 12 rounds fits at '
        '${size.width.toInt()}x${size.height.toInt()}', (final tester) async {
      tester.view
        ..physicalSize = size * 2
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: RoundSummaryScreen(
            scoreState: ScoreState(
              roundNumber: 13,
              teamOneTotal: 900,
              teamTwoTotal: 700,
              teamOneRound: 100,
              teamTwoRound: 0,
              playerRoundPoints: const {},
              roundComplete: true,
              targetScore: 1000,
              gameComplete: false,
              winningTeam: null,
              finishOrder: const [],
              rounds: [
                for (var i = 0; i < 12; i++)
                  RoundScore(
                    roundNumber: i + 1,
                    teamOnePoints: 75,
                    teamTwoPoints: 25,
                    teamOneCardPoints: 75,
                    teamTwoCardPoints: 25,
                    teamOneBonusPoints: 0,
                    teamTwoBonusPoints: 0,
                    finishOrder: const [],
                    roundEndType: RoundEndType.normal,
                  ),
              ],
              tichuCalls: const {},
            ),
            onBackHome: () {},
            onStartNextRound: () async {},
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Start next round'),
        100,
        scrollable: find.byWidgetPredicate(
          (final w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      );
      expect(find.text('Start next round'), findsOneWidget);
    });
  }
}
