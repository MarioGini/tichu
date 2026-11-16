import 'package:material_ui/material_ui.dart';

/// Inline yes/no decision banner for calling Grand Tichu.
class GrandTichuBanner extends StatelessWidget {
  const GrandTichuBanner({
    super.key,
    required this.selectNo,
    required this.isPending,
    required this.onDecision,
    required this.onToggle,
  });

  /// Whether "No" is currently the highlighted choice.
  final bool selectNo;

  /// Disables buttons when a decision is already being submitted.
  final bool isPending;

  /// Called with `true` for "Yes" (call Grand Tichu) or `false` for "No".
  final ValueChanged<bool> onDecision;

  /// Called when the user taps the non-highlighted button to toggle focus.
  final ValueChanged<bool> onToggle;

  @override
  Widget build(final BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Widget choice({required final String label, required final bool yes}) {
      final highlighted = yes ? !selectNo : selectNo;
      final onPressed = isPending
          ? null
          : highlighted
          ? () => onDecision(yes)
          : () => onToggle(!yes);
      const size = Size(72, 40);
      return highlighted
          ? ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                minimumSize: size,
                shape: const StadiumBorder(),
                backgroundColor: yes ? colorScheme.secondary : null,
                foregroundColor: yes ? Colors.black87 : null,
              ),
              child: Text(label),
            )
          : TextButton(
              onPressed: onPressed,
              style: TextButton.styleFrom(
                minimumSize: size,
                shape: const StadiumBorder(),
              ),
              child: Text(label),
            );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 4, 4, 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.32),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.local_fire_department,
                  size: 18,
                  color: colorScheme.secondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Grand Tichu?',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: Colors.white),
                ),
                const SizedBox(width: 12),
                choice(label: 'No', yes: false),
                const SizedBox(width: 4),
                choice(label: 'Yes', yes: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
