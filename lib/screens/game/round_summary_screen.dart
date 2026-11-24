import 'package:material_ui/material_ui.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/widgets/game_gradient_background.dart';

class RoundSummaryScreen extends StatelessWidget {
  const RoundSummaryScreen({
    super.key,
    required this.scoreState,
    required this.onBackHome,
    this.localTeam = 0,
    this.onStartNextRound,
  });

  final ScoreState scoreState;
  final VoidCallback onBackHome;

  /// The local player's team (0 = even seats, 1 = odd seats).
  final int localTeam;
  final Future<void> Function()? onStartNextRound;

  @override
  Widget build(BuildContext context) {
    final isMatchComplete = scoreState.gameComplete;
    final winningTeam = scoreState.winningTeam;
    final winnerLabel = switch (winningTeam) {
      null => "It's a tie!",
      final team when team == localTeam => 'Your team wins!',
      _ => 'Other team wins!',
    };

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: GameGradientBackground(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                // Scrolls when many rounds (or a landscape phone) make the
                // table taller than the screen.
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isMatchComplete
                                ? 'Match complete'
                                : 'Round ${scoreState.roundNumber} complete',
                            style: Theme.of(context).textTheme.titleLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          _ScoreSummaryTable(
                            scoreState: scoreState,
                            localTeam: localTeam,
                          ),
                          if (isMatchComplete) ...[
                            const SizedBox(height: 12),
                            Text('Target: ${scoreState.targetScore} points'),
                            const SizedBox(height: 8),
                            Text(
                              winnerLabel,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () async {
                                if (isMatchComplete) {
                                  onBackHome();
                                  return;
                                }
                                final startNextRound = onStartNextRound;
                                if (startNextRound == null) return;
                                await startNextRound();
                                if (!context.mounted) return;
                                Navigator.of(context).pop();
                              },
                              child: Text(
                                isMatchComplete
                                    ? 'Back to home'
                                    : 'Start next round',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreSummaryTable extends StatelessWidget {
  const _ScoreSummaryTable({required this.scoreState, required this.localTeam});

  final ScoreState scoreState;
  final int localTeam;

  @override
  Widget build(BuildContext context) {
    if (scoreState.rounds.isEmpty) {
      return const Text('No scoring data yet.');
    }

    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.labelLarge?.copyWith(
      color: Colors.white70,
    );
    final numberStyle = theme.textTheme.bodyMedium?.copyWith(
      color: Colors.white,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final totalStyle = theme.textTheme.titleMedium?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w800,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final usFirst = localTeam == 0;
    int us(int one, int two) => usFirst ? one : two;
    int them(int one, int two) => usFirst ? two : one;

    final rows = <TableRow>[
      TableRow(
        children: [
          _ScoreSummaryCell('Round', style: headerStyle),
          _ScoreSummaryCell('Your team', style: headerStyle),
          _ScoreSummaryCell('Other team', style: headerStyle),
        ],
      ),
      ...scoreState.rounds.map(
        (round) => TableRow(
          children: [
            _ScoreSummaryCell('${round.roundNumber}', style: numberStyle),
            _ScoreSummaryCell(
              '${us(round.teamOnePoints, round.teamTwoPoints)}',
              style: numberStyle,
            ),
            _ScoreSummaryCell(
              '${them(round.teamOnePoints, round.teamTwoPoints)}',
              style: numberStyle,
            ),
          ],
        ),
      ),
      TableRow(
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08)),
        children: [
          _ScoreSummaryCell('Total', style: totalStyle),
          _ScoreSummaryCell(
            '${us(scoreState.teamOneTotal, scoreState.teamTwoTotal)}',
            style: totalStyle?.copyWith(color: Colors.greenAccent),
          ),
          _ScoreSummaryCell(
            '${them(scoreState.teamOneTotal, scoreState.teamTwoTotal)}',
            style: totalStyle?.copyWith(color: Colors.orangeAccent),
          ),
        ],
      ),
    ];

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(0.8),
          1: FlexColumnWidth(),
          2: FlexColumnWidth(),
        },
        border: const TableBorder(
          horizontalInside: BorderSide(color: Colors.white10),
        ),
        children: rows,
      ),
    );
  }
}

class _ScoreSummaryCell extends StatelessWidget {
  const _ScoreSummaryCell(this.text, {this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Text(text, style: style, textAlign: TextAlign.center),
  );
}
