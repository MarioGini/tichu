import 'package:flutter/material.dart';

/// Shared gradient background used across all game screens.
class GameGradientBackground extends StatelessWidget {
  const GameGradientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(final BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [surface, surface.withValues(alpha: 0.7)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: child,
    );
  }
}
