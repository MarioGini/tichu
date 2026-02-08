import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;

import '../view_model/turn/tichu_data.dart';
import 'card_widget.dart';

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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availWidth = constraints.maxWidth;
          final n = cards.length;

          if (n == 0) {
            return SizedBox(height: resolvedHeight);
          }

          final cardW = CardWidget.normalWidth * scale;
          final cardH = CardWidget.normalHeight * scale;
          final marginR = 8 * scale;
          final selOffset = 8 * scale;
          final naturalStep = cardW + marginR;
          final totalNatural = n * naturalStep;
          final contentHeight = cardH + selOffset;

          if (totalNatural <= availWidth) {
            // Cards fit without overlap – centre them
            return SizedBox(
              height: contentHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < n; i++)
                    CardWidget(
                      card: cards[i],
                      isSelected: selectedIndexes.contains(i),
                      onTap: () => onCardTap(i),
                      scale: scale,
                    ),
                ],
              ),
            );
          }

          // Overlap mode: squeeze cards to fit available width.
          // Last card fully visible; earlier cards show their left edge.
          final step = math.max(
            18.0, // minimum visible sliver per card
            (availWidth - cardW - marginR) / math.max(1, n - 1),
          );

          return SizedBox(
            height: contentHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (int i = 0; i < n; i++)
                  Positioned(
                    left: i * step,
                    top: 0,
                    child: CardWidget(
                      card: cards[i],
                      isSelected: selectedIndexes.contains(i),
                      onTap: () => onCardTap(i),
                      scale: scale,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
