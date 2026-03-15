import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;

import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/widgets/card_widget.dart';
import 'package:tichu/widgets/overlapping_card_row.dart';
import 'package:tichu/widgets/played_card_size_scope.dart';

/// A slot that always reserves one card-width of space.
/// When [cards] is non-empty, they are rendered inside that space;
/// otherwise the slot is an empty placeholder that prevents layout shift.
class PendingPlaySlot extends StatelessWidget {
  const PendingPlaySlot({
    super.key,
    this.cards = const [],
    this.isPassed = false,
    this.alignment = Alignment.center,
  });

  final List<Card> cards;
  final bool isPassed;
  final Alignment alignment;

  @override
  Widget build(final BuildContext context) {
    if (cards.isEmpty || isPassed) {
      return const SizedBox.expand();
    }

    return LayoutBuilder(
      builder: (final context, final constraints) {
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : CardWidget.normalHeight;
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : CardWidget.normalWidth;

        final pendingCount = cards.length;
        const desiredMinVisible = 18.0;

        final scopedScale = PlayedCardSizeScope.maybeOf(context);
        final scaleByHeight =
            (math.max(0, maxHeight - 8) / (CardWidget.normalHeight + 8)).clamp(
              0.25,
              1.0,
            );
        final widthDenominator =
            CardWidget.normalWidth +
            math.max(0, pendingCount - 1) * desiredMinVisible;
        final scaleByWidth = (maxWidth / widthDenominator).clamp(0.25, 1.0);
        final preferredScale = scopedScale ?? scaleByHeight;
        final scale = math.min(
          preferredScale,
          math.min(scaleByHeight, scaleByWidth),
        );
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
                itemCount: pendingCount,
                cardWidth: cardW,
                cardHeight: cardH,
                spacing: spacing,
                minVisible: minVisible,
                height: rowHeight,
                itemBuilder: (final context, final index) => CardWidget(
                  card: cards[index],
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
