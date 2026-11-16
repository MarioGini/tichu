import 'package:material_ui/material_ui.dart';

/// Shared gradient background used across all game screens.
class GameGradientBackground extends StatelessWidget {
  const GameGradientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(final BuildContext context) {
    // Card-table felt: lighter in the middle, darker towards the edges.
    final surface = Theme.of(context).colorScheme.surface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        gradient: RadialGradient(
          radius: 1.1,
          colors: [
            Color.lerp(surface, const Color(0xFF2E8B57), 0.35)!,
            surface,
            Color.lerp(surface, Colors.black, 0.35)!,
          ],
          stops: const [0, 0.6, 1],
        ),
      ),
      child: child,
    );
  }
}
