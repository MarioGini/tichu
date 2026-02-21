import 'package:flutter/material.dart' hide Card;

import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/widgets/card_widget.dart';
import 'package:tichu/widgets/overlapping_card_row.dart';

class TrickDisplay extends StatelessWidget {
  const TrickDisplay({
    super.key,
    required this.cards,
    required this.currentWinnerLabel,
    this.dragonGiveLabel = '',
    required this.activeWish,
    this.trickPoints = 0,
    this.pendingOpponentLabel,
    this.pendingOpponentCards = const [],
    this.pendingOpponentPass = false,
  });

  final List<Card> cards;
  final String currentWinnerLabel;
  final String dragonGiveLabel;
  final CardFace activeWish;
  final int trickPoints;
  final String? pendingOpponentLabel;
  final List<Card> pendingOpponentCards;
  final bool pendingOpponentPass;

  @override
  Widget build(final BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white24, width: 0.8),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (final context, final constraints) {
        final isTight = constraints.maxHeight < 170;
        final cardScale =
            ((constraints.maxHeight * (isTight ? 0.35 : 0.42)) /
                    CardWidget.compactHeight)
                .clamp(0.3, 1.35);
        final cardW = CardWidget.compactWidth * cardScale;
        final cardH = CardWidget.compactHeight * cardScale;
        final rowHeight = cardH + 8;
        final labelGap = isTight ? 1.0 : 4.0;
        final blockGap = isTight ? 4.0 : 8.0;
        final wishScale = isTight ? cardScale * 0.42 : cardScale * 0.55;
        final cardsGap = cards.isEmpty ? 0.0 : blockGap;

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
                  ).textTheme.titleSmall?.copyWith(color: Colors.white),
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
            if (activeWish != CardFace.none) ...[
              CardWidget(
                card: Card(CardFace.mahJong, CardColor.special),
                isSelected: false,
                compact: true,
                scale: wishScale,
                overlayChipText: _wishLabel(activeWish),
              ),
              SizedBox(height: isTight ? 2 : 4),
            ],
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Trick points: $trickPoints',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ),
            SizedBox(height: cardsGap),
            if (cards.isEmpty)
              const SizedBox.shrink()
            else
              OverlappingCardRow(
                itemCount: cards.length,
                cardWidth: cardW,
                cardHeight: cardH,
                spacing: 6 * cardScale,
                minVisible: 12 * cardScale,
                height: rowHeight,
                itemBuilder: (final context, final index) => CardWidget(
                  card: cards[index],
                  isSelected: false,
                  compact: true,
                  scale: cardScale,
                ),
              ),
          ],
        );
      },
    ),
  );

  String _wishLabel(final CardFace face) => switch (face) {
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
