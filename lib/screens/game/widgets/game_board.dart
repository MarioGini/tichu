import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

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

        final topSection = [
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
        ];
        if (isPortrait) {
          // Phone portrait, like most mobile card games: the table takes all
          // free space (partner on top, opponents at the side edges, a large
          // trick in the middle), the action buttons sit directly above the
          // hand, and the hand is anchored to the bottom edge.
          return Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (final context, final table) =>
                      _portraitTable(table.maxWidth, table.maxHeight),
                ),
              ),
              actionBar,
              Padding(
                padding: EdgeInsets.fromLTRB(hPad, 2, hPad, 6),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: h * 0.34),
                  child: handArea,
                ),
              ),
            ],
          );
        }

        return PlayedCardSizeScope(
          cardScale: playedCardScale,
          child: Column(
            children: [
              ...topSection,
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

  Widget _portraitTable(final double w, final double h) {
    const pad = 4.0;
    const gap = 4.0;
    final op = math.min(w * 0.22, math.min(h * 0.2, 96)).toDouble();
    // Trick: as large as the space between the side opponents allows.
    final trickW = math.min<double>(w - 2 * (op + pad + gap), 300);
    final trickH = math
        .min(h - 2 * (op + gap) - 8, CardWidget.normalHeight + 56)
        .clamp(80.0, 400.0);
    final laneH = math.max(0, trickH - 44).toDouble();
    final playedCardScale =
        (math.max(0, laneH - 8) / (CardWidget.normalHeight + 8)).clamp(
          0.25,
          1.0,
        );
    final pendingH = math.min(laneH * 0.6, op);
    final pendingW = CardWidget.normalWidth * playedCardScale * 1.6;

    return PlayedCardSizeScope(
      cardScale: playedCardScale,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: pad,
            left: (w - op) / 2,
            child: SizedBox.square(dimension: op, child: topOpponent),
          ),
          if (reserveTopPendingSlot)
            Positioned(
              top: pad + op + gap,
              left: (w - pendingW) / 2,
              width: pendingW,
              height: pendingH,
              child: topPendingSlot,
            ),
          Positioned(
            left: pad,
            top: (h - op) / 2,
            child: SizedBox.square(dimension: op, child: leftOpponent),
          ),
          if (reserveSidePendingSlots)
            Positioned(
              left: pad,
              top: (h + op) / 2 + gap,
              width: op,
              height: pendingH,
              child: leftPendingSlot,
            ),
          Positioned(
            right: pad,
            top: (h - op) / 2,
            child: SizedBox.square(dimension: op, child: rightOpponent),
          ),
          if (reserveSidePendingSlots)
            Positioned(
              right: pad,
              top: (h + op) / 2 + gap,
              width: op,
              height: pendingH,
              child: rightPendingSlot,
            ),
          Positioned(
            left: (w - trickW) / 2,
            top: (h - trickH) / 2 + op * 0.25,
            width: trickW,
            height: trickH,
            child: trickArea,
          ),
        ],
      ),
    );
  }
}
