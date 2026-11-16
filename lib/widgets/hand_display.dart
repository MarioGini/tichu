import 'dart:math' as math;

import 'package:material_ui/material_ui.dart' hide Card;

import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/widgets/card_widget.dart';
import 'package:tichu/widgets/overlapping_card_row.dart';
import 'package:tichu/widgets/player_state_frame.dart';

/// Displays the player's hand cards, scaling to fit the parent's constraints.
///
/// Card size is the smaller of
///  * the height fit: availableHeight / (cardHeight + selectionOffset), and
///  * the width fit: a full 14-card hand overlaps so that every card still
///    shows its rank corner ([visibleFraction] of a card width).
/// Sizing for a full hand keeps cards the same size all round long (as in
/// most mobile card games) instead of growing as the hand empties.
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

  /// Share of a card's width left visible when cards overlap.
  static const double visibleFraction = 0.34;

  /// Hand size the card size is computed for.
  static const int referenceHandSize = 14;

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
        final headerH = header != null ? 26.0 : 0.0;
        final positionH = finishPosition != null ? 24.0 : 0.0;
        final cardBudget =
            availH - containerPad - selOffset - headerH - positionH - 1.0;

        // Scale cards to fit the height budget and the width of a full hand.
        const framePad = 16.0;
        final widthScale =
            (availW - framePad) /
            (CardWidget.normalWidth *
                (1 + (referenceHandSize - 1) * visibleFraction));
        final scale = math
            .min(cardBudget / CardWidget.normalHeight, widthScale)
            .clamp(0.25, 1.0);
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

  /// Hand played out: a slim full-width bar with the header and position.
  Widget _buildEmpty(final BuildContext context) {
    if (header == null && finishPosition == null) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: buildPlayerStateFrameDecoration(
        isActive: isActive,
        isFinished: isFinished,
        borderRadius: 16,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?header,
            if (finishPosition != null) ...[
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.greenAccent),
                ),
                child: Text(
                  'Out #$finishPosition',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: Colors.greenAccent),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
