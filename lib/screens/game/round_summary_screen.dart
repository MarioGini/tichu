import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/screens/game/widgets/trick_event_overlay.dart';
import 'package:tichu/widgets/game_gradient_background.dart';

class RoundSummaryScreen extends StatefulWidget {
  const RoundSummaryScreen({
    super.key,
    required this.scoreState,
    required this.onBackHome,
    this.onStartNextRound,
    this.tichuSuccessMessage,
  });

  final ScoreState scoreState;
  final VoidCallback onBackHome;
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
      unawaited(_celebrationController.forward());
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
    final winnerLabel = switch (widget.scoreState.winningTeam) {
      0 => 'Your team wins!',
      1 => 'Other team wins!',
      _ => "It's a tie!",
    };

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Tichu'),
        ),
        body: GameGradientBackground(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(24),
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
                            _ScoreSummaryTable(scoreState: widget.scoreState),
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
  const _ScoreSummaryTable({required this.scoreState});

  final ScoreState scoreState;

  @override
  Widget build(final BuildContext context) {
    if (scoreState.rounds.isEmpty) {
      return const Text('No scoring data yet.');
    }

    final headerStyle = Theme.of(context).textTheme.labelLarge;
    final numberStyle = Theme.of(context).textTheme.bodyMedium;

    final rows = <TableRow>[
      TableRow(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
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
            _ScoreSummaryCell('${round.teamOnePoints}', style: numberStyle),
            _ScoreSummaryCell('${round.teamTwoPoints}', style: numberStyle),
          ],
        ),
      ),
      TableRow(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        children: [
          _ScoreSummaryCell('Total', style: headerStyle),
          _ScoreSummaryCell('${scoreState.teamOneTotal}', style: headerStyle),
          _ScoreSummaryCell('${scoreState.teamTwoTotal}', style: headerStyle),
        ],
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Center(
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
          children: rows,
        ),
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
    child: Text(text, style: style),
  );
}
