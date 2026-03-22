import 'package:flutter/material.dart';

import 'package:tichu/widgets/trick_display.dart';

extension BombOverlayExtension on TrickDisplay {
  Widget withBombOverlay({
    required final bool showOverlay,
    required final Animation<Offset> slide,
    required final Animation<double> scale,
  }) => Stack(
    fit: StackFit.expand,
    alignment: Alignment.center,
    children: [
      this,
      IgnorePointer(
        child: AnimatedOpacity(
          opacity: showOverlay ? 1 : 0,
          duration: const Duration(milliseconds: 140),
          child: EventSlamOverlay(
            slide: slide,
            scale: scale,
            icon: Icons.local_fire_department,
            label: 'BOOM',
          ),
        ),
      ),
    ],
  );
}

class EventSlamOverlay extends StatelessWidget {
  const EventSlamOverlay({
    super.key,
    required this.slide,
    required this.scale,
    required this.icon,
    required this.label,
    this.gradientColors,
    this.iconColor,
    this.labelColor,
  });

  final Animation<Offset> slide;
  final Animation<double> scale;
  final IconData icon;
  final String label;
  final List<Color>? gradientColors;
  final Color? iconColor;
  final Color? labelColor;

  @override
  Widget build(final BuildContext context) => SlideTransition(
    position: slide,
    child: ScaleTransition(
      scale: scale,
      child: Container(
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors:
                gradientColors ??
                [
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
              Icon(icon, color: iconColor ?? Colors.white, size: 42),
              Text(
                label,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: labelColor ?? Colors.white,
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
