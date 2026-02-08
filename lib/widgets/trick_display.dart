import 'package:flutter/material.dart' hide Card;

import '../view_model/turn/tichu_data.dart';
import 'card_widget.dart';
import 'overlapping_card_row.dart';

class TrickDisplay extends StatelessWidget {
  const TrickDisplay({
    super.key,
    required this.cards,
    required this.currentWinnerLabel,
    this.dragonGiveLabel = '',
    required this.activeWish,
    this.trickPoints = 0,
    this.pendingAiLabel,
    this.pendingAiCards = const [],
    this.pendingAiPass = false,
  });

  final List<Card> cards;
  final String currentWinnerLabel;
  final String dragonGiveLabel;
  final CardFace activeWish;
  final int trickPoints;
  final String? pendingAiLabel;
  final List<Card> pendingAiCards;
  final bool pendingAiPass;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isTight = constraints.maxHeight < 170;
          final cardScale =
              ((constraints.maxHeight * (isTight ? 0.26 : 0.32)) /
                      CardWidget.compactHeight)
                  .clamp(0.5, 1.0);
          final cardW = CardWidget.compactWidth * cardScale;
          final cardH = CardWidget.compactHeight * cardScale;
          final rowHeight = cardH + 10;
          final labelGap = isTight ? 4.0 : 6.0;
          final blockGap = isTight ? 6.0 : 12.0;

          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (currentWinnerLabel.isNotEmpty) ...[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    currentWinnerLabel,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.white),
                  ),
                ),
                SizedBox(height: labelGap),
              ],
              if (dragonGiveLabel.isNotEmpty) ...[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    dragonGiveLabel,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: Colors.amber),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(height: labelGap),
              ],
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Wish: ${_wishLabel(activeWish)}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
              ),
              SizedBox(height: isTight ? 2 : 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Trick points: $trickPoints',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
              ),
              SizedBox(height: blockGap),
              if (cards.isEmpty)
                Column(
                  children: [
                    Icon(Icons.style_outlined, color: Colors.white54, size: 28),
                    const SizedBox(height: 8),
                    Text(
                      'No cards on table',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                    ),
                  ],
                )
              else
                OverlappingCardRow(
                  itemCount: cards.length,
                  cardWidth: cardW,
                  cardHeight: cardH,
                  spacing: 6 * cardScale,
                  minVisible: 12 * cardScale,
                  height: rowHeight,
                  itemBuilder: (context, index) {
                    return CardWidget(
                      card: cards[index],
                      isSelected: false,
                      compact: true,
                      scale: cardScale,
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  String _wishLabel(CardFace face) {
    return switch (face) {
      CardFace.none => 'None',
      CardFace.mahJong => 'Mah Jong',
      CardFace.dragon => 'Dragon',
      CardFace.phoenix => 'Phoenix',
      CardFace.dog => 'Dog',
      CardFace.ace => 'A',
      CardFace.king => 'K',
      CardFace.queen => 'Q',
      CardFace.jack => 'J',
      CardFace.ten => '10',
      CardFace.nine => '9',
      CardFace.eight => '8',
      CardFace.seven => '7',
      CardFace.six => '6',
      CardFace.five => '5',
      CardFace.four => '4',
      CardFace.three => '3',
      CardFace.two => '2',
    };
  }
}
