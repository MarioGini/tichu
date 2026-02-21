import 'package:flutter/material.dart';

/// Banner displayed when the game (match) is over, showing the winning team
/// and a "Continue" button that pops the screen.
class MatchEndBanner extends StatelessWidget {
  const MatchEndBanner({super.key, required this.winningTeam, this.onContinue});

  /// 0 = human team, 1 = opponent team.
  final int winningTeam;

  /// If null, defaults to `Navigator.of(context).pop()`.
  final VoidCallback? onContinue;

  @override
  Widget build(final BuildContext context) => Center(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '\u{1F3C6} ${winningTeam == 0 ? 'Your team wins!' : 'Other team wins!'}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: onContinue ?? () => Navigator.of(context).pop(),
            child: const Text('Continue'),
          ),
        ],
      ),
    ),
  );
}
