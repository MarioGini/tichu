import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:tichu/widgets/card_widget.dart';
import 'package:tichu/widgets/game_gradient_background.dart';
import 'package:tichu/widgets/played_card_size_scope.dart';

/// Unified game board layout for all screen sizes.
///
/// Fixed-size sections: top opponent, middle row (opponents + trick).
/// Remaining space: split between hand area (Expanded) and action bar.
/// No manual pixel math for gaps — just `const SizedBox(height: 4)`.
class GameBoard extends StatelessWidget {
  const GameBoard({
    super.key,
    required this.topOpponent,
    required this.leftOpponent,
    required this.rightOpponent,
    required this.trickArea,
    required this.handArea,
    required this.actionBar,
    this.reserveTopPendingSlot = true,
    this.reserveSidePendingSlots = true,
    this.topPendingSlot = const SizedBox.shrink(),
    this.leftPendingSlot = const SizedBox.shrink(),
    this.rightPendingSlot = const SizedBox.shrink(),
  });

  final Widget topOpponent;
  final Widget leftOpponent;
  final Widget rightOpponent;
  final Widget trickArea;
  final Widget handArea;
  final Widget actionBar;
  final bool reserveTopPendingSlot;
  final bool reserveSidePendingSlots;

  /// Slot between top opponent and trick area.
  final Widget topPendingSlot;

  /// Slot between the left opponent box and the trick area.
  final Widget leftPendingSlot;

  /// Slot between the trick area and the right opponent box.
  final Widget rightPendingSlot;

  @override
  Widget build(final BuildContext context) => GameGradientBackground(
    child: LayoutBuilder(
      builder: (final context, final constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final isPortrait = h > w && w < 600;
        final laneGap = isPortrait ? 4.0 : 6.0;

        final opSize = math.min(
          w * (isPortrait ? 0.20 : 0.16),
          h * (isPortrait ? 0.14 : 0.16),
        );
        // Trick area height: tall enough for full-size cards + labels.
        final trickH = math.min(
          h * (isPortrait ? 0.26 : 0.28),
          CardWidget.normalHeight + 56,
        );
        final cardLaneH = math.max(0, trickH - 44).toDouble();
        final laneScale = (cardLaneH / CardWidget.normalHeight).clamp(
          0.25,
          1.0,
        );
        final preferredTrickW = math
            .min(w * (isPortrait ? 0.28 : 0.24), 260)
            .toDouble();
        final rowW = math.max(0, w - (isPortrait ? 8 : 16)).toDouble();
        final pendingLaneBudget = reserveSidePendingSlots
            ? (2 * laneGap + 2 * CardWidget.normalWidth * laneScale)
            : 0.0;
        final maxTrickW = math
            .max(120, rowW - 2 * opSize - 2 * laneGap - pendingLaneBudget)
            .toDouble();
        final trickW = math.min(preferredTrickW, maxTrickW);
        final preferredSideSlotW = CardWidget.normalWidth * laneScale;
        final maxSideSlotW = reserveSidePendingSlots
            ? math
                  .max(0, (rowW - 2 * opSize - trickW - 4 * laneGap) / 2)
                  .toDouble()
            : 0.0;
        final sideSlotW = reserveSidePendingSlots
            ? math.min(preferredSideSlotW, maxSideSlotW)
            : 0.0;
        final topPendingH = reserveTopPendingSlot ? cardLaneH : 0.0;
        final playedCardScale =
            (math.max(0, cardLaneH - 8) / (CardWidget.normalHeight + 8)).clamp(
              0.25,
              1.0,
            );
        final rowHeight = math.max(opSize, trickH);
        final hPad = isPortrait ? 4.0 : 8.0;

        return PlayedCardSizeScope(
          cardScale: playedCardScale,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SizedBox.square(dimension: opSize, child: topOpponent),
              ),
              if (reserveTopPendingSlot)
                SizedBox(
                  height: topPendingH,
                  child: Center(
                    child: SizedBox(width: sideSlotW, child: topPendingSlot),
                  ),
                ),
              const SizedBox(height: 4),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad),
                child: SizedBox(
                  height: rowHeight,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox.square(dimension: opSize, child: leftOpponent),
                      SizedBox(width: laneGap),
                      if (reserveSidePendingSlots) ...[
                        SizedBox(
                          width: sideSlotW,
                          height: cardLaneH,
                          child: leftPendingSlot,
                        ),
                        SizedBox(width: laneGap),
                      ],
                      SizedBox(width: trickW, height: trickH, child: trickArea),
                      if (reserveSidePendingSlots) ...[
                        SizedBox(width: laneGap),
                        SizedBox(
                          width: sideSlotW,
                          height: cardLaneH,
                          child: rightPendingSlot,
                        ),
                      ],
                      SizedBox(width: laneGap),
                      SizedBox.square(dimension: opSize, child: rightOpponent),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Remaining space: hand + action bar pack to top;
              // leftover goes below action bar inside this Expanded.
              Expanded(
                child: Column(
                  children: [
                    Flexible(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: hPad),
                        child: handArea,
                      ),
                    ),
                    actionBar,
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
