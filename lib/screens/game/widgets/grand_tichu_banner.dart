import 'package:flutter/material.dart';

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
            'Grand Tichu?',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: selectNo
                ? ElevatedButton(
                    onPressed: isPending ? null : () => onDecision(false),
                    child: const Text('No'),
                  )
                : TextButton(
                    onPressed: isPending ? null : () => onToggle(true),
                    child: const Text('No'),
                  ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 64,
            child: !selectNo
                ? ElevatedButton(
                    onPressed: isPending ? null : () => onDecision(true),
                    child: const Text('Yes'),
                  )
                : TextButton(
                    onPressed: isPending ? null : () => onToggle(false),
                    child: const Text('Yes'),
                  ),
          ),
        ],
      ),
    ),
  );
}
