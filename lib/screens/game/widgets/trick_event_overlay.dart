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
            child: BombSlamOverlay(slide: slide, scale: scale),
          ),
        ),
      ],
    );
}

class BombSlamOverlay extends StatelessWidget {
  const BombSlamOverlay({super.key, required this.slide, required this.scale});

  final Animation<Offset> slide;
  final Animation<double> scale;

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
