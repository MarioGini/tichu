import 'package:flutter/material.dart' hide Card;

import '../view_model/turn/tichu_data.dart';
import 'card_widget.dart';
import 'overlapping_card_row.dart';

class HandDisplay extends StatelessWidget {
  const HandDisplay({
    super.key,
    required this.cards,
    required this.selectedIndexes,
    required this.onCardTap,
    this.targetHeight,
  });

  final List<Card> cards;
  final Set<int> selectedIndexes;
  final ValueChanged<int> onCardTap;
  final double? targetHeight;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final resolvedHeight =
        targetHeight ?? (screenHeight * 0.18).clamp(80.0, 160.0);
    final scale = ((resolvedHeight - 12) / CardWidget.normalHeight).clamp(
      0.4,
      1.2,
    );

    if (cards.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final n = cards.length;

          final cardW = CardWidget.normalWidth * scale;
          final cardH = CardWidget.normalHeight * scale;
          final marginR = 8 * scale;
          final selOffset = 8 * scale;
          final contentHeight = cardH + selOffset;

          return OverlappingCardRow(
            itemCount: n,
            cardWidth: cardW,
            cardHeight: cardH,
            spacing: marginR,
            minVisible: 18.0,
            height: contentHeight,
            itemBuilder: (context, index) {
              return CardWidget(
                card: cards[index],
                isSelected: selectedIndexes.contains(index),
                onTap: () => onCardTap(index),
                scale: scale,
              );
            },
          );
        },
      ),
    );
  }
}
