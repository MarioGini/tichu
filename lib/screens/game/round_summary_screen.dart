import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/screens/game/widgets/trick_event_overlay.dart';
import 'package:tichu/widgets/game_gradient_background.dart';

class RoundSummaryScreen extends StatefulWidget {
  const RoundSummaryScreen({
    super.key,
    required this.scoreState,
    required this.onBackHome,
    this.localTeam = 0,
    this.onStartNextRound,
    this.tichuSuccessMessage,
  });

  final ScoreState scoreState;
  final VoidCallback onBackHome;

  /// The local player's team (0 = even seats, 1 = odd seats).
  final int localTeam;
  final Future<void> Function()? onStartNextRound;
  final String? tichuSuccessMessage;

  @override
  State<RoundSummaryScreen> createState() => _RoundSummaryScreenState();
}

class _RoundSummaryScreenState extends State<RoundSummaryScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _celebrationController;
  late final Animation<Offset> _celebrationSlide;
  late final Animation<double> _celebrationScale;
  bool _showCelebration = false;

  String? get _celebrationMessage => widget.tichuSuccessMessage;

  String get _celebrationLabel =>
      widget.scoreState.gameComplete ? 'MATCH' : 'TICHU';

  @override
  void initState() {
    super.initState();
    _celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
      reverseDuration: const Duration(milliseconds: 300),
    );
    _celebrationSlide =
        Tween<Offset>(begin: const Offset(0, -1.6), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _celebrationController,
            curve: Curves.easeInCubic,
            reverseCurve: Curves.easeIn,
          ),
        );
    _celebrationScale = Tween<double>(begin: 0.9, end: 1).animate(
      CurvedAnimation(
        parent: _celebrationController,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      ),
    );

    if (_celebrationMessage != null) {
      _showCelebration = true;
      _celebrationController.forward();
    }
  }

  void _dismissCelebration() {
    if (!mounted) return;
    setState(() {
      _showCelebration = false;
    });
  }

  @override
  void dispose() {
    _celebrationController.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final isMatchComplete = widget.scoreState.gameComplete;
    final winningTeam = widget.scoreState.winningTeam;
    final winnerLabel = switch (winningTeam) {
      null => "It's a tie!",
      final team when team == widget.localTeam => 'Your team wins!',
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
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isMatchComplete
                                  ? 'Match complete'
                                  : 'Round ${widget.scoreState.roundNumber} complete',
                              style: Theme.of(context).textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            _ScoreSummaryTable(
                              scoreState: widget.scoreState,
                              localTeam: widget.localTeam,
                            ),
                            if (isMatchComplete) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Target: ${widget.scoreState.targetScore} points',
                              ),
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
                                    widget.onBackHome();
                                    return;
                                  }
                                  final startNextRound =
                                      widget.onStartNextRound;
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
                      if (_showCelebration && _celebrationMessage != null)
                        AnimatedOpacity(
                          opacity: _showCelebration ? 1 : 0,
                          duration: const Duration(milliseconds: 140),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              EventSlamOverlay(
                                slide: _celebrationSlide,
                                scale: _celebrationScale,
                                icon: Icons.emoji_events,
                                label: _celebrationLabel,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _celebrationMessage!,
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(color: Colors.white),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 14),
                              FilledButton(
                                onPressed: _dismissCelebration,
                                child: const Text('Next'),
                              ),
                            ],
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
    );
  }
}

class _ScoreSummaryTable extends StatelessWidget {
  const _ScoreSummaryTable({required this.scoreState, required this.localTeam});

  final ScoreState scoreState;
  final int localTeam;

  @override
  Widget build(final BuildContext context) {
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
    int us(final int one, final int two) => usFirst ? one : two;
    int them(final int one, final int two) => usFirst ? two : one;

    final rows = <TableRow>[
      TableRow(
        children: [
          _ScoreSummaryCell('Round', style: headerStyle),
          _ScoreSummaryCell('Your team', style: headerStyle),
          _ScoreSummaryCell('Other team', style: headerStyle),
        ],
      ),
      ...scoreState.rounds.map(
        (final round) => TableRow(
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
  Widget build(final BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Text(text, style: style, textAlign: TextAlign.center),
  );
}
