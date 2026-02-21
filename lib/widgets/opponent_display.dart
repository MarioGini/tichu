import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;

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

  @override
  Widget build(final BuildContext context) {
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
        final pendingHeight = (squareSide * 0.28).clamp(34.0, 64.0);

        final box = SizedBox.square(
          dimension: squareSide,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.all(6),
            padding: const EdgeInsets.all(8),
            decoration: _boxDecoration(colorScheme),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _nameRow(context, colorScheme),
                  const SizedBox(height: 3),
                  _infoLine(context),
                  const SizedBox(height: 4),
                  _statusPill(context, colorScheme),
                  if (finishPosition != null)
                    buildPlayerOutLabel(context, finishPosition!),
                  _tichuBadge(context, isHorizontal: false),
                ],
              ),
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
            pendingPlacement != PendingPlacement.below;
        final sideGap = reservesSidePendingLane ? 6.0 : 0.0;
        final pendingWidth = reservesSidePendingLane
            ? (maxWidth * 0.22).clamp(24.0, 56.0)
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _nameRow(context, colorScheme),
                  const SizedBox(height: 3),
                  _infoLine(context),
                  const SizedBox(height: 4),
                  _statusPill(context, colorScheme),
                  if (finishPosition != null)
                    buildPlayerOutLabel(context, finishPosition!),
                  _tichuBadge(context, isHorizontal: false),
                ],
              ),
            ),
          ),
        );

        if (pendingPlacement == PendingPlacement.below) {
          if (!hasPending) {
            return Center(child: box);
          }

          final pendingHeight = (squareSide * 0.35).clamp(48.0, 110.0);
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

        final pendingBox = SizedBox(
          width: pendingWidth,
          height: squareSide,
          child: hasPending
              ? _pendingWidget(context, alignment: Alignment.center)
              : const SizedBox.shrink(),
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

  // ───── shared building blocks ─────

  BoxDecoration _boxDecoration(final ColorScheme colorScheme) =>
      buildPlayerStateFrameDecoration(
        isActive: isActive,
        isFinished: isFinished,
        borderRadius: 12,
      );

  Widget _nameRow(final BuildContext context, final ColorScheme colorScheme) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: colorScheme.onSurface.withValues(alpha: 0.9),
            size: 22,
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: Colors.white),
          ),
        ],
      );

  Widget _infoLine(final BuildContext context) => Text(
    showPoints ? '$cardCount cards · $teamScore pts' : '$cardCount cards',
    style: Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
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
  }) {
    if (!tichuDeclared && !grandTichuDeclared) return const SizedBox.shrink();

    final badgeColor = grandTichuDeclared ? Colors.deepOrange : Colors.orange;
    final label = grandTichuDeclared ? 'GRAND' : 'TICHU';

    return Padding(
      padding: EdgeInsets.only(
        left: isHorizontal ? 8 : 0,
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
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : CardWidget.compactHeight * 0.7 + 8;
        const framePadding = 6.0;
        final safeHeight = math.max<double>(0, maxHeight - framePadding);
        final scale = math.min(
          0.7,
          safeHeight / (CardWidget.compactHeight + 8),
        );
        final cardW = CardWidget.compactWidth * scale;
        final cardH = CardWidget.compactHeight * scale;
        final spacing = 6 * scale;
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
                minVisible: 10 * scale,
                height: rowHeight,
                itemBuilder: (final context, final index) => CardWidget(
                  card: pendingCards[index],
                  isSelected: false,
                  compact: true,
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
