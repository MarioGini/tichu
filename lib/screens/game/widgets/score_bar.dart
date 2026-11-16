import 'package:material_ui/material_ui.dart';

import 'package:tichu/game/scoring/score_tracker.dart';

/// Compact team score shown in the game's app bar: "Us 340 : 285 Them",
/// with the round number and target score underneath.
class ScoreBar extends StatelessWidget {
  const ScoreBar({
    super.key,
    required this.scoreState,
    required this.isTeamOne,
  });

  final ScoreState scoreState;

  /// Whether the local player is on team one (even seats).
  final bool isTeamOne;

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    final us = isTeamOne ? scoreState.teamOneTotal : scoreState.teamTwoTotal;
    final them = isTeamOne ? scoreState.teamTwoTotal : scoreState.teamOneTotal;
    final big = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.15,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final label = theme.textTheme.labelMedium?.copyWith(color: Colors.white70);

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Us ', style: label),
                Text(
                  '$us',
                  style: big?.copyWith(
                    color: us >= them ? Colors.greenAccent : Colors.white,
                  ),
                ),
                Text('  :  ', style: big?.copyWith(color: Colors.white54)),
                Text(
                  '$them',
                  style: big?.copyWith(
                    color: them > us ? Colors.orangeAccent : Colors.white,
                  ),
                ),
                Text(' Them', style: label),
              ],
            ),
            Text(
              'Round ${scoreState.roundNumber} · to ${scoreState.targetScore}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white54,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
