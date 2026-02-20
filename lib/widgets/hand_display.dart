import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;

import '../game/turn/tichu_data.dart';
import 'card_widget.dart';
import 'overlapping_card_row.dart';
import 'player_state_frame.dart';

class HandDisplay extends StatelessWidget {
  const HandDisplay({
    super.key,
    required this.cards,
    required this.selectedIndexes,
    required this.onCardTap,
    this.isActive = false,
    this.isFinished = false,
    this.finishPosition,
    this.targetHeight,
    this.header,
  });

  final List<Card> cards;
  final Set<int> selectedIndexes;
  final ValueChanged<int> onCardTap;
  final bool isActive;
  final bool isFinished;
  final int? finishPosition;
  final double? targetHeight;
  final Widget? header;

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
      if (header != null || finishPosition != null) {
        return Center(
          child: IntrinsicWidth(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: buildPlayerStateFrameDecoration(
                isActive: isActive,
                isFinished: isFinished,
                borderRadius: 16,
                idleAlpha: 0.2,
              ),
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
        );
      }
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, outerConstraints) {
        final n = cards.length;
        final cardW = CardWidget.normalWidth * scale;
        final cardH = CardWidget.normalHeight * scale;
        final marginR = 8 * scale;
        final selOffset = 8 * scale;
        final naturalWidth = cardW + math.max(0, n - 1) * (cardW + marginR);
        // Content + container padding (8 horizontal each side).
        final desiredWidth = naturalWidth + 16;
        final containerWidth = desiredWidth.clamp(
          0.0,
          outerConstraints.maxWidth,
        );

        return Center(
          child: Container(
            width: containerWidth,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: buildPlayerStateFrameDecoration(
              isActive: isActive,
              isFinished: isFinished,
              borderRadius: 16,
              idleAlpha: 0.2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (header != null) ...[header!, const SizedBox(height: 4)],
                if (finishPosition != null)
                  buildPlayerOutLabel(context, finishPosition!),
                Padding(
                  padding: EdgeInsets.only(top: selOffset),
                  child: OverlappingCardRow(
                    itemCount: n,
                    cardWidth: cardW,
                    cardHeight: cardH,
                    spacing: marginR,
                    minVisible: 18.0,
                    height: cardH,
                    itemBuilder: (context, index) {
                      return CardWidget(
                        card: cards[index],
                        isSelected: selectedIndexes.contains(index),
                        onTap: () => onCardTap(index),
                        scale: scale,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
