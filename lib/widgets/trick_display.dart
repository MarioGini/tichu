import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;

import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/widgets/card_widget.dart';
import 'package:tichu/widgets/overlapping_card_row.dart';
import 'package:tichu/widgets/played_card_size_scope.dart';

class TrickDisplay extends StatelessWidget {
  const TrickDisplay({
    super.key,
    required this.cards,
    required this.currentWinnerLabel,
    this.dragonGiveLabel = '',
    required this.activeWish,
    this.trickPoints = 0,
    this.showTrickPoints = true,
  });

  final List<Card> cards;
  final String currentWinnerLabel;
  final String dragonGiveLabel;
  final CardFace activeWish;
  final int trickPoints;
  final bool showTrickPoints;

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
        final availH = constraints.maxHeight - 12; // container padding
        final placeholderScale = (availH / CardWidget.normalHeight).clamp(
          0.25,
          1.0,
        );
        final gap = 2.0 + 2.0 * placeholderScale;

        final hasMahjongInTrick = cards.any(
          (final card) => card.face == CardFace.mahJong,
        );
        final showWish = activeWish != CardFace.none && !hasMahjongInTrick;

        final showHeaderLine =
            currentWinnerLabel.isNotEmpty || dragonGiveLabel.isNotEmpty;
        final reservedHeaderH = showHeaderLine ? 36 : 0;
        final reservedWishH = showWish
            ? CardWidget.compactHeight * placeholderScale * 0.5 + gap
            : 0;
        final reservedPointsH = showTrickPoints ? 18 : 0;
        final cardTopGap = cards.isNotEmpty ? math.max(1, gap * 0.45) : 0.0;
        final reservedGapH = cardTopGap.toDouble();
        final cardAreaH = math.max(
          0,
          availH -
              reservedHeaderH -
              reservedWishH -
              reservedPointsH -
              reservedGapH -
              4,
        );
        final scopedScale = PlayedCardSizeScope.maybeOf(context);
        final heightScale = (cardAreaH / (CardWidget.normalHeight + 8)).clamp(
          0.25,
          1.0,
        );
        final widthDenominator =
            CardWidget.normalWidth + math.max(0, cards.length - 1) * 18;
        final widthScale = (constraints.maxWidth / widthDenominator).clamp(
          0.25,
          1.0,
        );
        final preferredScale = scopedScale ?? heightScale;
        final scale = math.min(
          preferredScale,
          math.min(heightScale, widthScale),
        );
        final cardW = CardWidget.normalWidth * scale;
        final cardH = CardWidget.normalHeight * scale;

        return Column(
          children: [
            if (currentWinnerLabel.isNotEmpty) ...[
              Text(
                currentWinnerLabel,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: gap),
            ],
            if (dragonGiveLabel.isNotEmpty) ...[
              Text(
                dragonGiveLabel,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: Colors.amber),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: gap),
            ],
            if (showWish) ...[
              CardWidget(
                card: Card(CardFace.mahJong, CardColor.special),
                isSelected: false,
                compact: true,
                scale: scale * 0.5,
                overlayChipText: _wishLabel(activeWish),
              ),
              SizedBox(height: gap),
            ],
            if (showTrickPoints)
              Text(
                'Trick points: $trickPoints',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            if (cards.isNotEmpty) ...[
              SizedBox(height: cardTopGap.toDouble()),
              Expanded(
                child: Align(
                  child: OverlappingCardRow(
                    itemCount: cards.length,
                    cardWidth: cardW,
                    cardHeight: cardH,
                    spacing: 6 * scale,
                    minVisible: cardW * 0.35,
                    height: cardH + 8,
                    itemBuilder: (final context, final index) {
                      final card = cards[index];
                      final wishOverlay =
                          activeWish != CardFace.none &&
                              card.face == CardFace.mahJong
                          ? _wishLabel(activeWish)
                          : null;
                      return CardWidget(
                        card: card,
                        isSelected: false,
                        scale: scale,
                        overlayChipText: wishOverlay,
                      );
                    },
                  ),
                ),
              ),
            ],
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
