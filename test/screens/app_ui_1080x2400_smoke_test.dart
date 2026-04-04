import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/screens/game/round_summary_screen.dart';
import 'package:tichu/screens/game/widgets/options_dialog.dart';
import 'package:tichu/screens/game/widgets/wish_dialog.dart';
import 'package:tichu/screens/home/home_screen.dart';

void main() {
  Future<void> setTargetViewport(final WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  ScoreState buildSummaryState() {
    final rounds = List<RoundScore>.generate(
      10,
      (final index) => RoundScore(
        roundNumber: index + 1,
        teamOnePoints: 90 + (index % 3) * 10,
        teamTwoPoints: 110 - (index % 3) * 10,
        teamOneCardPoints: 60,
        teamTwoCardPoints: 40,
        teamOneBonusPoints: 30,
        teamTwoBonusPoints: 70,
        finishOrder: const ['player-0', 'player-2', 'player-1', 'player-3'],
        roundEndType: RoundEndType.normal,
      ),
    );

    return ScoreState(
      roundNumber: 11,
      teamOneTotal: 980,
      teamTwoTotal: 920,
      teamOneRound: 100,
      teamTwoRound: 100,
      playerRoundPoints: const {
        'player-0': 40,
        'player-2': 60,
        'player-1': 30,
        'player-3': 70,
      },
      roundComplete: true,
      targetScore: 1000,
      gameComplete: false,
      winningTeam: null,
      finishOrder: const ['player-0', 'player-2', 'player-1', 'player-3'],
      rounds: rounds,
      tichuCalls: const {},
    );
  }

  testWidgets('home screen renders without overflow at 1080x2400', (
    final tester,
  ) async {
    await setTargetViewport(tester);

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump();

    expect(find.text('TICHU'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('round summary renders without overflow at 1080x2400', (
    final tester,
  ) async {
    await setTargetViewport(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: RoundSummaryScreen(
          scoreState: buildSummaryState(),
          onBackHome: () {},
          onStartNextRound: () async {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Round 11 complete'), findsOneWidget);
    expect(find.text('Start next round'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('options dialog content fits at 1080x2400', (final tester) async {
    await setTargetViewport(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OptionsDialog(
            aiSuggestionEnabled: true,
            opponentDelay: 2,
            autoPassEnabled: false,
            soundEnabled: true,
            onAiSuggestionChanged: (final _) {},
            onOpponentDelayChanged: (final _) {},
            onAutoPassChanged: (final _) {},
            onSoundChanged: (final _) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Options'), findsOneWidget);
    expect(find.text('Sound effects'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wish dialog content fits at 1080x2400', (final tester) async {
    await setTargetViewport(tester);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: WishDialog(defaultWish: CardFace.nine)),
      ),
    );
    await tester.pump();

    expect(find.text('Declare a wish'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
