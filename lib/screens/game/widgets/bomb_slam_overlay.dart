import 'package:flutter/material.dart';

import '../../../widgets/trick_display.dart';

extension BombOverlayExtension on TrickDisplay {
  Widget withBombOverlay({
    required bool showOverlay,
    required Animation<Offset> slide,
    required Animation<double> scale,
    required bool showMatchOverlay,
    required Animation<Offset> matchSlide,
    required Animation<double> matchScale,
  }) {
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        this,
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: showOverlay ? 1 : 0,
            duration: const Duration(milliseconds: 140),
            child: BombSlamOverlay(slide: slide, scale: scale),
          ),
        ),
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: showMatchOverlay ? 1 : 0,
            duration: const Duration(milliseconds: 140),
            child: MatchCelebrationOverlay(
              slide: matchSlide,
              scale: matchScale,
            ),
          ),
        ),
      ],
    );
  }
}

class BombSlamOverlay extends StatelessWidget {
  const BombSlamOverlay({super.key, required this.slide, required this.scale});

  final Animation<Offset> slide;
  final Animation<double> scale;

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: slide,
      child: ScaleTransition(
        scale: scale,
        child: Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                Colors.orangeAccent,
                Colors.deepOrange.shade700,
                Colors.black87,
              ],
              stops: const [0.0, 0.6, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.local_fire_department,
                  color: Colors.white,
                  size: 42,
                ),
                Text(
                  'BOOM',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MatchCelebrationOverlay extends StatelessWidget {
  const MatchCelebrationOverlay({
    super.key,
    required this.slide,
    required this.scale,
  });

  final Animation<Offset> slide;
  final Animation<double> scale;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SlideTransition(
      position: slide,
      child: ScaleTransition(
        scale: scale,
        child: Container(
          width: 190,
          height: 190,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                colorScheme.primaryContainer,
                colorScheme.secondaryContainer,
                colorScheme.tertiaryContainer,
              ],
              stops: const [0.0, 0.65, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.5),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.celebration,
                  color: colorScheme.onPrimaryContainer,
                  size: 46,
                ),
                Text(
                  'MATCH!',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
