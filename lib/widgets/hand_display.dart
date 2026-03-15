import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;

import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/widgets/card_widget.dart';
import 'package:tichu/widgets/overlapping_card_row.dart';
import 'package:tichu/widgets/player_state_frame.dart';

/// Displays the player's hand cards, scaling to fit the parent's constraints.
///
/// Uses `LayoutBuilder` to read available height, then derives card scale
/// from that. No manual overhead constants — just:
///   scale = availableHeight / (cardHeight + selectionOffset)
class HandDisplay extends StatelessWidget {
  const HandDisplay({
    super.key,
    required this.cards,
    required this.selectedIndexes,
    required this.onCardTap,
    this.isActive = false,
    this.isFinished = false,
    this.finishPosition,
    this.header,
  });

  final List<Card> cards;
  final Set<int> selectedIndexes;
  final ValueChanged<int> onCardTap;
  final bool isActive;
  final bool isFinished;
  final int? finishPosition;
  final Widget? header;

  @override
  Widget build(final BuildContext context) {
    if (cards.isEmpty) {
      return _buildEmpty(context);
    }

    return LayoutBuilder(
      builder: (final context, final constraints) {
        final availH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 180.0;
        final availW = constraints.maxWidth;

        // Reserve space for header, padding, selection offset.
        const containerPad = 12.0; // vertical padding (6+6)
        const selOffset = 8.0;
        final headerH = header != null ? 34.0 : 0.0;
        final positionH = finishPosition != null ? 24.0 : 0.0;
        final cardBudget =
            availH - containerPad - selOffset - headerH - positionH - 1.0;

        // Scale cards to fit the budget.
        final scale = (cardBudget / CardWidget.normalHeight).clamp(0.25, 1.0);
        final cardW = CardWidget.normalWidth * scale;
        final cardH = CardWidget.normalHeight * scale;
        final spacing = 8.0 * scale;
        final scaledSelOffset = selOffset * scale;

        // Container width: fit cards or fill available.
        final n = cards.length;
        final naturalW = cardW + math.max(0, n - 1) * (cardW + spacing) + 16;
        final containerW = math.min(naturalW, availW);

        return Align(
          alignment: Alignment.topCenter,
          heightFactor: 1,
          child: Container(
            width: containerW,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: buildPlayerStateFrameDecoration(
              isActive: isActive,
              isFinished: isFinished,
              borderRadius: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (header != null) ...[header!, const SizedBox(height: 4)],
                if (finishPosition != null)
                  buildPlayerOutLabel(context, finishPosition!),
                Padding(
                  padding: EdgeInsets.only(top: scaledSelOffset),
                  child: OverlappingCardRow(
                    itemCount: n,
                    cardWidth: cardW,
                    cardHeight: cardH,
                    spacing: spacing,
                    height: cardH,
                    itemBuilder: (final context, final index) => CardWidget(
                      card: cards[index],
                      isSelected: selectedIndexes.contains(index),
                      onTap: () => onCardTap(index),
                      scale: scale,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmpty(final BuildContext context) {
    if (header == null && finishPosition == null) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (final context, final constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : CardWidget.normalHeight;
        final maxH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : CardWidget.normalHeight;
        final side = math.min(math.min(maxW, maxH), 128).toDouble();

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox.square(
            dimension: side,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: buildPlayerStateFrameDecoration(
                isActive: isActive,
                isFinished: isFinished,
                borderRadius: 16,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ?header,
                    if (finishPosition != null)
                      buildPlayerOutLabel(context, finishPosition!),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
