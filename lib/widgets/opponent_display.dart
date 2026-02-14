import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;

import '../game/turn/tichu_data.dart';
import 'card_widget.dart';
import 'overlapping_card_row.dart';

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
  final List<Card> pendingCards;
  final bool pendingPass;
  final PendingPlacement pendingPlacement;

  @override
  Widget build(BuildContext context) {
    final isHorizontal = alignment == Axis.horizontal;
    final hasPending = pendingCards.isNotEmpty;

    if (isHorizontal) {
      return _buildHorizontalLayout(context, hasPending);
    }
    return _buildVerticalLayout(context, hasPending);
  }

  /// Horizontal layout for the top opponent (player 2 / partner).
  Widget _buildHorizontalLayout(BuildContext context, bool hasPending) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        final gap = hasPending ? 4.0 : 0.0;
        final pendingHeight = hasPending
            ? (maxHeight * 0.42).clamp(64.0, 140.0).toDouble()
            : 0.0;
        final boxSide = math.max(
          0.0,
          math.min(maxWidth, maxHeight - pendingHeight - gap),
        );

        final box = SizedBox.square(
          dimension: boxSide,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.all(6),
            padding: const EdgeInsets.all(8),
            decoration: _boxDecoration(colorScheme),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _nameRow(context, colorScheme),
                  const SizedBox(height: 3),
                  _infoLine(context),
                  const SizedBox(height: 4),
                  _statusPill(context, colorScheme),
                  if (finishPosition != null) _finishLabel(context),
                  _tichuBadge(context, isHorizontal: false),
                ],
              ),
            ),
          ),
        );

        if (!hasPending) {
          return Center(child: box);
        }

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            box,
            SizedBox(height: gap),
            SizedBox(height: pendingHeight, child: _pendingWidget(context)),
          ],
        );
      },
    );
  }

  /// Vertical layout for side opponents (players 1 & 3).
  /// The player box is forced to be square via AspectRatio.
  /// Pending cards are rendered *below* the box, outside it.
  Widget _buildVerticalLayout(BuildContext context, bool hasPending) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        final sideGap = hasPending ? 6.0 : 0.0;
        final hasSidePending =
            hasPending && pendingPlacement != PendingPlacement.below;
        final pendingWidth = hasSidePending
            ? (maxWidth * 0.35).clamp(48.0, 96.0).toDouble()
            : 0.0;
        final availableWidth = hasSidePending
            ? math.max(0.0, maxWidth - pendingWidth - sideGap)
            : maxWidth;
        final squareSide = math.max(0.0, math.min(maxHeight, availableWidth));

        final box = SizedBox.square(
          dimension: squareSide,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.all(6),
            padding: const EdgeInsets.all(8),
            decoration: _boxDecoration(colorScheme),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _nameRow(context, colorScheme),
                  const SizedBox(height: 3),
                  _infoLine(context),
                  const SizedBox(height: 4),
                  _statusPill(context, colorScheme),
                  if (finishPosition != null) _finishLabel(context),
                  _tichuBadge(context, isHorizontal: false),
                ],
              ),
            ),
          ),
        );

        if (!hasPending) {
          return Center(child: box);
        }

        if (pendingPlacement == PendingPlacement.below) {
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
                  child: _pendingWidget(
                    context,
                    alignment: Alignment.topCenter,
                  ),
                ),
              ),
            ],
          );
        }

        final pendingBox = SizedBox(
          width: pendingWidth,
          height: squareSide,
          child: Align(
            alignment: Alignment.center,
            child: _pendingWidget(context, alignment: Alignment.center),
          ),
        );

        final rowChildren = pendingPlacement == PendingPlacement.left
            ? [pendingBox, SizedBox(width: sideGap), box]
            : [box, SizedBox(width: sideGap), pendingBox];

        return Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: rowChildren,
          ),
        );
      },
    );
  }

  // ───── shared building blocks ─────

  BoxDecoration _boxDecoration(ColorScheme colorScheme) {
    final Color borderColor;
    final double borderWidth;
    if (isFinished) {
      borderColor = Colors.greenAccent;
      borderWidth = 2.5;
    } else if (tichuDeclared && !grandTichuDeclared) {
      borderColor = Colors.orange;
      borderWidth = 2.5;
    } else if (isActive) {
      borderColor = Colors.amber;
      borderWidth = 2;
    } else {
      borderColor = Colors.white24;
      borderWidth = 1;
    }

    return BoxDecoration(
      color: Colors.black.withValues(alpha: isActive ? 0.35 : 0.2),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: borderColor, width: borderWidth),
      boxShadow: (tichuDeclared && !grandTichuDeclared)
          ? [
              BoxShadow(
                color: Colors.orange.withValues(alpha: 0.35),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ]
          : null,
    );
  }

  Widget _nameRow(BuildContext context, ColorScheme colorScheme) {
    return Row(
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
  }

  Widget _infoLine(BuildContext context) {
    return Text(
      '$cardCount cards · $teamScore pts',
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: Colors.white70),
    );
  }

  Widget _statusPill(BuildContext context, ColorScheme colorScheme) {
    final String label;
    final Color accent;
    if (pendingPass) {
      label = 'Pass';
      accent = Colors.amberAccent;
    } else if (isFinished) {
      label = 'Out';
      accent = Colors.greenAccent;
    } else if (isActive) {
      label = 'Their turn';
      accent = colorScheme.secondary;
    } else {
      label = 'Waiting';
      accent = Colors.white70;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: pendingPass
            ? Colors.amber.withValues(alpha: 0.15)
            : isFinished
            ? Colors.greenAccent.withValues(alpha: 0.18)
            : isActive
            ? colorScheme.secondary.withValues(alpha: 0.18)
            : Colors.white10,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: pendingPass
              ? Colors.amberAccent
              : isFinished
              ? Colors.greenAccent
              : isActive
              ? colorScheme.secondary
              : Colors.white24,
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: accent),
      ),
    );
  }

  Widget _finishLabel(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        'Out #$finishPosition',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: Colors.greenAccent),
      ),
    );
  }

  Widget _tichuBadge(BuildContext context, {required bool isHorizontal}) {
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
    BuildContext context, {
    Alignment alignment = Alignment.topCenter,
  }) {
    if (pendingPass) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amberAccent),
        ),
        child: Text(
          'PASS',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.amberAccent,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : CardWidget.compactHeight * 0.7 + 8;
        final safeHeight = math.max(0.0, maxHeight - 6);
        final scale = math.min(0.7, safeHeight / CardWidget.compactHeight);
        final cardW = CardWidget.compactWidth * scale;
        final cardH = CardWidget.compactHeight * scale;
        final spacing = 6 * scale;
        final rowHeight = math.min(maxHeight, cardH + 6);

        return ClipRect(
          child: Align(
            alignment: alignment,
            child: OverlappingCardRow(
              itemCount: pendingCards.length,
              cardWidth: cardW,
              cardHeight: cardH,
              spacing: spacing,
              minVisible: 10 * scale,
              height: rowHeight,
              itemBuilder: (context, index) {
                return CardWidget(
                  card: pendingCards[index],
                  isSelected: true,
                  compact: true,
                  scale: scale,
                );
              },
            ),
          ),
        );
      },
    );
  }
}
