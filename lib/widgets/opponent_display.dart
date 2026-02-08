import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;

import '../view_model/turn/tichu_data.dart';
import 'card_widget.dart';

enum PendingPlacement { below, left, right }

class OpponentDisplay extends StatelessWidget {
  const OpponentDisplay({
    super.key,
    required this.name,
    required this.cardCount,
    required this.isActive,
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
    final hasPending = pendingPass || pendingCards.isNotEmpty;

    if (isHorizontal) {
      return _buildHorizontalLayout(context, hasPending);
    }
    return _buildVerticalLayout(context, hasPending);
  }

  /// Horizontal layout for the top opponent (player 2 / partner).
  Widget _buildHorizontalLayout(BuildContext context, bool hasPending) {
    final colorScheme = Theme.of(context).colorScheme;

    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: _boxDecoration(colorScheme),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _nameRow(context, colorScheme),
                  const SizedBox(height: 4),
                  _infoLine(context),
                  const SizedBox(height: 6),
                  _statusPill(context, colorScheme),
                  if (finishPosition != null) _finishLabel(context),
                ],
              ),
            ),
          ),
          _tichuBadge(context, isHorizontal: true),
        ],
      ),
    );

    if (!hasPending) {
      return box;
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        box,
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _pendingWidget(context),
        ),
      ],
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
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              box,
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _pendingWidget(context),
              ),
            ],
          );
        }

        final pendingBox = SizedBox(
          width: pendingWidth,
          child: _pendingWidget(context),
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
    if (grandTichuDeclared) {
      borderColor = Colors.deepOrange;
      borderWidth = 2.5;
    } else if (tichuDeclared) {
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
      boxShadow: (tichuDeclared || grandTichuDeclared)
          ? [
              BoxShadow(
                color: (grandTichuDeclared ? Colors.deepOrange : Colors.orange)
                    .withValues(alpha: 0.35),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? colorScheme.secondary.withValues(alpha: 0.18)
            : Colors.white10,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isActive ? colorScheme.secondary : Colors.white24,
        ),
      ),
      child: Text(
        isActive ? 'Their turn' : 'Waiting',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: isActive ? colorScheme.secondary : Colors.white70,
        ),
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

  Widget _pendingWidget(BuildContext context) {
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
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final card in pendingCards)
          CardWidget(card: card, isSelected: false, compact: true, scale: 0.6),
      ],
    );
  }
}
