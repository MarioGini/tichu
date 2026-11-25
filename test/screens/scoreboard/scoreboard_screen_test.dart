import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tichu/scoreboard/scoreboard_model.dart';
import 'package:tichu/scoreboard/scoreboard_store.dart';
import 'package:tichu/screens/scoreboard/round_entry_screen.dart';
import 'package:tichu/screens/scoreboard/scoreboard_screen.dart';
import 'package:tichu/theme/app_theme.dart';

Widget _app(ScoreboardStore store) => MaterialApp(
  theme: AppTheme.darkTheme,
  home: ScoreboardScreen(store: store),
);

void main() {
  testWidgets('start a match, add a round with a Tichu, totals update', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(412, 915) * 2
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final store = InMemoryScoreboardStore();
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    expect(find.text('New match'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Us');
    await tester.enterText(find.byType(TextField).last, 'Them');
    await tester.tap(find.text('Start match'));
    await tester.pumpAndSettle();

    expect(find.text('Add round 1'), findsOneWidget);
    await tester.tap(find.text('Add round 1'));
    await tester.pumpAndSettle();

    // Team A calls Tichu (defaults to made); cards stay 50 : 50.
    await tester.tap(find.text('Tichu').first);
    await tester.pumpAndSettle();
    expect(find.text('+150'), findsOneWidget);
    expect(find.text('+50'), findsOneWidget);

    // Marking it failed flips the bonus.
    await tester.tap(find.byTooltip('Failed'));
    await tester.pumpAndSettle();
    expect(find.text('\u221250'), findsOneWidget);
    await tester.tap(find.byTooltip('Made'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('150'), findsWidgets);
    expect(find.text('50'), findsWidgets);
    final saved = await store.loadCurrent();
    expect(saved!.teamNames, ['Us', 'Them']);
    expect(saved.totalFor(0), 150);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the winner once the target is reached', (tester) async {
    final store = InMemoryScoreboardStore(
      ScoreboardGame.start(
        teamNames: const ['Us', 'Them'],
        targetScore: 500,
        now: DateTime(2026),
      ).copyWith(
        rounds: const [
          ScoreboardRound(doubleVictoryTeam: 0),
          ScoreboardRound(doubleVictoryTeam: 0),
          ScoreboardRound(cardPointsTeamA: 100),
        ],
      ),
    );
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();
    expect(find.text('Us win!'), findsOneWidget);
    expect(find.text('500'), findsWidgets);
  });

  testWidgets('both partners can call; only one call can be made', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(412, 915) * 2
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const RoundEntryScreen(teamNames: ['Us', 'Them'], roundNumber: 1),
      ),
    );
    // Team A: Grand Tichu (made), then Tichu (failed, partner went out).
    await tester.tap(find.text('Grand').first);
    await tester.pump();
    await tester.tap(find.text('Tichu').first);
    await tester.pumpAndSettle();

    // 50 + 200 - 100; team A has no add buttons left, team B still has.
    expect(find.text('+150'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Tichu'), findsOneWidget);

    // Making the Tichu fails the Grand Tichu: 50 - 200 + 100.
    await tester.tap(find.byTooltip('Made').last);
    await tester.pumpAndSettle();
    expect(find.text('\u221250'), findsOneWidget);
  });

  ScoreboardGame twoRounds() =>
      ScoreboardGame.start(
        teamNames: const ['Us', 'Them'],
        now: DateTime(2026),
      ).copyWith(
        rounds: const [
          ScoreboardRound(cardPointsTeamA: 70),
          ScoreboardRound(cardPointsTeamA: 20),
        ],
      );

  testWidgets('undo re-inserts the deleted round and keeps later rounds', (
    tester,
  ) async {
    final store = InMemoryScoreboardStore(twoRounds());
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Undo last round'));
    await tester.pumpAndSettle();
    expect((await store.loadCurrent())!.rounds, hasLength(1));

    // Editing a round while the snack bar is up drops the stale Undo.
    await tester.tap(find.text('+70'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);

    await tester.tap(find.text('Add round 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await store.loadCurrent())!.rounds, hasLength(2));

    // A fresh delete + Undo restores exactly that round.
    await tester.tap(find.byTooltip('Undo last round'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    final rounds = (await store.loadCurrent())!.rounds;
    expect(rounds.map((r) => r.cardPointsTeamA), [70, 50]);
  });

  testWidgets('confirmed new match is not restored on reopen', (tester) async {
    final store = InMemoryScoreboardStore(twoRounds());
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New match'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'New match'));
    await tester.pumpAndSettle();

    final saved = (await store.loadCurrent())!;
    expect(saved.rounds, isEmpty);
    expect(saved.teamNames, ['Us', 'Them']);
  });

  testWidgets('rounds run top to bottom, newest last', (tester) async {
    await tester.pumpWidget(_app(InMemoryScoreboardStore(twoRounds())));
    await tester.pumpAndSettle();
    final first = tester.getTopLeft(find.text('+70'));
    final second = tester.getTopLeft(find.text('+20'));
    expect(first.dy, lessThan(second.dy));
  });
}
