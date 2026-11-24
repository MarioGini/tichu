import 'dart:math' as math;

import 'package:material_ui/material_ui.dart' hide Card;

import 'package:tichu/widgets/player_state_frame.dart';

class OpponentDisplay extends StatelessWidget {
  const OpponentDisplay({
    super.key,
    required this.name,
    required this.cardCount,
    required this.isActive,
    required this.isFinished,
    required this.tichuDeclared,
    required this.grandTichuDeclared,
    required this.finishPosition,
    required this.icon,
    required this.teamScore,
    this.showPoints = true,
    this.pill = false,
  });

  final String name;
  final int cardCount;
  final bool isActive;
  final bool isFinished;
  final bool tichuDeclared;
  final bool grandTichuDeclared;
  final int? finishPosition;
  final IconData icon;
  final int teamScore;
  final bool showPoints;

  /// Draw a wide, low seat pill that fills the given box (phone landscape)
  /// instead of a square tile.
  final bool pill;

  @override
  Widget build(BuildContext context) {
    if (pill) return _buildPill(context);
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => Center(
        child: SizedBox.square(
          dimension: math.max<double>(
            0,
            math.min(constraints.maxWidth, constraints.maxHeight),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.all(6),
            padding: const EdgeInsets.all(8),
            decoration: _boxDecoration(colorScheme),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _tileContent(context, colorScheme),
            ),
          ),
        ),
      ),
    );
  }

  /// Wide seat pill: avatar with card count, name and points, badges.
  Widget _buildPill(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: _boxDecoration(colorScheme)
          .copyWith(borderRadius: BorderRadius.circular(999)),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _avatar(colorScheme, size: 34),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: Colors.white, height: 1.1),
                ),
                Text(
                  finishPosition != null
                      ? 'Out #$finishPosition'
                      : showPoints
                      ? '$teamScore pts'
                      : '$cardCount cards',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: finishPosition != null
                        ? Colors.greenAccent
                        : Colors.white60,
                  ),
                ),
              ],
            ),
            if (tichuDeclared || grandTichuDeclared) ...[
              const SizedBox(width: 6),
              _tichuBadge(context, isHorizontal: true, compact: true),
            ],
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }

  // ───── shared building blocks ─────

  Widget _tileContent(BuildContext context, ColorScheme colorScheme) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _avatar(colorScheme, size: 34),
      const SizedBox(height: 2),
      Text(
        name,
        maxLines: 1,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: Colors.white),
      ),
      // Points and Tichu badge share one row; the finish position sits on
      // the avatar badge, so finished tiles stay as compact as live ones.
      if (showPoints || tichuDeclared || grandTichuDeclared)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showPoints)
                Text(
                  '$teamScore pts',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: Colors.white60),
                ),
              if (showPoints && (tichuDeclared || grandTichuDeclared))
                const SizedBox(width: 6),
              _tichuBadge(context, isHorizontal: true, compact: true),
            ],
          ),
        ),
      if (isFinished && finishPosition == null)
        _statusPill(context, colorScheme),
    ],
  );

  /// Round avatar with the seat icon and a card-count badge.
  Widget _avatar(ColorScheme colorScheme, {required double size}) {
    final ringColor = isFinished
        ? Colors.greenAccent
        : isActive
        ? Colors.amber
        : Colors.white24;
    return SizedBox(
      width: size + 8,
      height: size + 4,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 2,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primaryContainer,
                    colorScheme.primaryContainer.withValues(alpha: 0.55),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: ringColor, width: isActive ? 2 : 1),
              ),
              child: Icon(
                icon,
                size: size * 0.55,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              constraints: const BoxConstraints(minWidth: 20),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: finishPosition != null
                    ? Colors.greenAccent
                    : cardCount == 0
                    ? Colors.white24
                    : Colors.white,
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 3),
                ],
              ),
              child: Text(
                finishPosition != null ? '#$finishPosition' : '$cardCount',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF0B3B2A),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _boxDecoration(ColorScheme colorScheme) =>
      buildPlayerStateFrameDecoration(
        isActive: isActive,
        isFinished: isFinished,
        borderRadius: 12,
      );

  Widget _statusPill(BuildContext context, ColorScheme colorScheme) {
    if (!isFinished) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.greenAccent),
      ),
      child: Text(
        'Out',
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: Colors.greenAccent),
      ),
    );
  }

  Widget _tichuBadge(
    BuildContext context, {
    required bool isHorizontal,
    bool compact = false,
  }) {
    if (!tichuDeclared && !grandTichuDeclared) return const SizedBox.shrink();

    final badgeColor = grandTichuDeclared ? Colors.deepOrange : Colors.orange;
    final label = grandTichuDeclared ? 'GRAND' : 'TICHU';

    return Padding(
      padding: EdgeInsets.only(
        left: isHorizontal && !compact ? 8 : 0,
        top: isHorizontal ? 0 : 6,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: badgeColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}
