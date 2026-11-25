import 'package:material_ui/material_ui.dart';

/// Banner displayed when the game (match) is over, showing the winning team
/// and a "Continue" button that pops the screen.
class MatchEndBanner extends StatelessWidget {
  const MatchEndBanner({super.key, required this.winningTeam, this.onContinue});

  /// 0 = human team, 1 = opponent team.
  /// 0 = the local player's team won, 1 = the other team.
  final int winningTeam;

  /// If null, defaults to `Navigator.of(context).pop()`.
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final won = winningTeam == 0;
    final color = won ? Colors.amber : Colors.orangeAccent;
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.8)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                won ? Icons.emoji_events : Icons.flag_outlined,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                won ? 'Your team wins!' : 'Other team wins!',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(width: 14),
              FilledButton(
                onPressed: onContinue ?? () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(shape: const StadiumBorder()),
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
