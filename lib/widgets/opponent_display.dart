import 'dart:math' as math;

import 'package:material_ui/material_ui.dart' hide Card;

import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/widgets/card_widget.dart';
import 'package:tichu/widgets/overlapping_card_row.dart';
import 'package:tichu/widgets/player_state_frame.dart';

enum PendingPlacement { below, left, right }

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
    required this.alignment,
    required this.icon,
    required this.teamScore,
    this.showPoints = true,
    this.pendingCards = const [],
    this.pendingPass = false,
    this.pendingPlacement = PendingPlacement.below,
    this.pill = false,
  });

  final String name;
  final int cardCount;
  final bool isActive;
  final bool isFinished;
  final bool tichuDeclared;
  final bool grandTichuDeclared;
  final int? finishPosition;
  final Axis alignment;
  final IconData icon;
  final int teamScore;
  final bool showPoints;
  final List<Card> pendingCards;
  final bool pendingPass;
  final PendingPlacement pendingPlacement;

  /// Draw a wide, low seat pill that fills the given box (phone landscape)
  /// instead of a square tile.
  final bool pill;

  @override
  Widget build(final BuildContext context) {
    if (pill) return _buildPill(context);
    final isHorizontal = alignment == Axis.horizontal;
    final hasPending = pendingCards.isNotEmpty;

    if (isHorizontal) {
      return _buildHorizontalLayout(context, hasPending);
    }
    return _buildVerticalLayout(context, hasPending);
  }

  /// Horizontal layout for the top opponent (player 2 / partner).
  Widget _buildHorizontalLayout(
    final BuildContext context,
    final bool hasPending,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (final context, final constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        const gap = 6.0;
        final squareSide = math.max<double>(0, math.min(maxWidth, maxHeight));
        final pendingHeight = (squareSide * 0.35).clamp(48.0, 80.0);

        final box = SizedBox.square(
          dimension: squareSide,
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
        );

        if (!hasPending) {
          return Center(child: box);
        }

        return SizedBox(
          width: maxWidth,
          height: maxHeight,
          child: Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: [
              box,
              Positioned(
                top: squareSide + gap,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: pendingHeight,
                  child: _pendingWidget(context, alignment: Alignment.center),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Vertical layout for side opponents (players 1 & 3).
  /// The player box is forced to be square via AspectRatio.
  /// Pending cards are rendered *below* the box, outside it.
  Widget _buildVerticalLayout(
    final BuildContext context,
    final bool hasPending,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (final context, final constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        final reservesSidePendingLane =
            hasPending && pendingPlacement != PendingPlacement.below;
        final sideGap = reservesSidePendingLane ? 6.0 : 0.0;
        final pendingWidth = reservesSidePendingLane
            ? (maxWidth * 0.44).clamp(62.0, 150.0)
            : 0.0;
        final availableWidth = reservesSidePendingLane
            ? math.max<double>(0, maxWidth - pendingWidth - sideGap)
            : maxWidth;
        final squareSide = math.max<double>(
          0,
          math.min(maxHeight, availableWidth),
        );

        final box = SizedBox.square(
          dimension: squareSide,
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
        );

        if (pendingPlacement == PendingPlacement.below) {
          if (!hasPending) {
            return Center(child: box);
          }

          final pendingHeight = (squareSide * 0.40).clamp(56.0, 120.0);
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              box,
              SizedBox(height: sideGap),
              SizedBox(
                height: pendingHeight,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: _pendingWidget(context),
                ),
              ),
            ],
          );
        }

        if (!reservesSidePendingLane) {
          return Center(child: box);
        }

        final pendingBox = SizedBox(
          width: pendingWidth,
          height: squareSide,
          child: _pendingWidget(context, alignment: Alignment.center),
        );

        final rowChildren = pendingPlacement == PendingPlacement.left
            ? [pendingBox, SizedBox(width: sideGap), box]
            : [box, SizedBox(width: sideGap), pendingBox];

        return Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: rowChildren),
        );
      },
    );
  }

  /// Wide seat pill: avatar with card count, name and points, badges.
  Widget _buildPill(final BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: _boxDecoration(
        colorScheme,
      ).copyWith(borderRadius: BorderRadius.circular(999)),
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
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    height: 1.1,
                  ),
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

  Widget _tileContent(
    final BuildContext context,
    final ColorScheme colorScheme,
  ) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _avatar(colorScheme, size: 34),
      const SizedBox(height: 2),
      Text(
        name,
        maxLines: 1,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(color: Colors.white),
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
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: Colors.white60),
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
  Widget _avatar(final ColorScheme colorScheme, {required final double size}) {
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

  BoxDecoration _boxDecoration(final ColorScheme colorScheme) =>
      buildPlayerStateFrameDecoration(
        isActive: isActive,
        isFinished: isFinished,
        borderRadius: 12,
      );

  Widget _statusPill(
    final BuildContext context,
    final ColorScheme colorScheme,
  ) {
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
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: Colors.greenAccent),
      ),
    );
  }

  Widget _tichuBadge(
    final BuildContext context, {
    required final bool isHorizontal,
    final bool compact = false,
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

  Widget _pendingWidget(
    final BuildContext context, {
    final Alignment alignment = Alignment.topCenter,
  }) {
    if (pendingPass) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (final context, final constraints) {
        final pendingCount = pendingCards.length;
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : CardWidget.normalHeight * 0.55 + 8;
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : CardWidget.normalWidth;
        const framePadding = 6.0;
        const desiredMinVisible = 18.0;
        final safeHeight = math.max<double>(0, maxHeight - framePadding);
        final scaleByHeight = safeHeight / CardWidget.normalHeight;
        final widthDenominator =
            CardWidget.normalWidth +
            math.max(0, pendingCount - 1) * desiredMinVisible;
        final scaleByWidth = maxWidth / widthDenominator;
        final scale = math.min(scaleByHeight, scaleByWidth).clamp(0.42, 1.25);
        final cardW = CardWidget.normalWidth * scale;
        final cardH = CardWidget.normalHeight * scale;
        final spacing = 6 * scale;
        final minVisible = (desiredMinVisible * scale).clamp(6.0, 24.0);
        final rowHeight = math.min(maxHeight, cardH);

        return SizedBox.expand(
          child: ClipRect(
            child: Align(
              alignment: alignment,
              child: OverlappingCardRow(
                itemCount: pendingCards.length,
                cardWidth: cardW,
                cardHeight: cardH,
                spacing: spacing,
                minVisible: minVisible,
                height: rowHeight,
                itemBuilder: (final context, final index) => CardWidget(
                  card: pendingCards[index],
                  isSelected: false,
                  scale: scale,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
