import 'dart:math' as math;

import 'package:flutter/material.dart';

class GameBoard extends StatelessWidget {
  const GameBoard({
    super.key,
    required this.topOpponent,
    required this.leftOpponent,
    required this.rightOpponent,
    required this.trickArea,
    required this.handArea,
    required this.actionBar,
  });

  final Widget topOpponent;
  final Widget leftOpponent;
  final Widget rightOpponent;
  final Widget trickArea;
  final Widget handArea;
  final Widget actionBar;

  @override
  Widget build(final BuildContext context) => LayoutBuilder(
    builder: (final context, final constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      final isPortraitMobile = h > w && w < 600;

      // Proportional scaling factors derived from constraints.
      // tw: 0→1 as width goes 320→1200; th: 0→1 as height goes 400→900.
      final tw = ((w - 320) / 880).clamp(0.0, 1.0);
      final th = ((h - 400) / 500).clamp(0.0, 1.0);

      final boardGap = isPortraitMobile ? 0.0 : (2 + 10 * th);
      final topPadH = (8 + 8 * tw).clamp(4.0, 16.0);
      final topPadV = isPortraitMobile ? 2.0 : (4 + 4 * th);
      final topPadding = EdgeInsets.fromLTRB(topPadH, topPadV, topPadH, 0);
      final sidePad = (4 + 4 * tw).clamp(4.0, 8.0);
      final handPadH = isPortraitMobile ? 4.0 : (6 + 6 * tw).clamp(4.0, 12.0);
      final handPadV = isPortraitMobile ? 2.0 : (2 + 4 * th).clamp(2.0, 6.0);
      final handPadding = EdgeInsets.fromLTRB(handPadH, 0, handPadH, handPadV);
      final trickToHandGap = isPortraitMobile ? 0.0 : (2 + 4 * th);
      final sideToCenterGap = isPortraitMobile
          ? (6 + 4 * tw).clamp(4.0, 12.0)
          : (12 + 18 * tw).clamp(8.0, 30.0);
      final areaWidth = math.max<double>(0, w - (sidePad * 2));
      final maxSideWidth = math.min(
        areaWidth * (0.18 + 0.04 * (1 - tw)),
        (142 + 98 * tw).clamp(100.0, 240.0),
      );
      final sideWidth = math.max<double>(
        0,
        math.min(maxSideWidth, (areaWidth - sideToCenterGap * 2) / 3),
      );
      // Opponent size: 12% of height on portrait, scaling 14–23% on wider.
      final opponentFraction = isPortraitMobile
          ? 0.12
          : (0.14 + 0.09 * th).clamp(0.12, 0.23);
      final sharedOpponentSize = math.min(sideWidth, h * opponentFraction);
      const topPendingGap = 6.0;
      final topPendingLaneHeight = (sharedOpponentSize * 0.28).clamp(
        34.0,
        64.0,
      );
      final topToMiddleGap = isPortraitMobile
          ? 0.0
          : topPendingGap + topPendingLaneHeight;
      final topHeight = sharedOpponentSize + topPadding.vertical;

      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: isPortraitMobile
            // Portrait: single column with top opponent, trick, hand, action bar.
            // spaceEvenly distributes remaining space as equal gaps.
            ? Column(
                children: [
                  SizedBox(
                    height: topHeight,
                    child: Padding(
                      padding: topPadding,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: sharedOpponentSize,
                            maxHeight: sharedOpponentSize,
                          ),
                          child: topOpponent,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _buildPortraitLayout(
                      sidePad: sidePad,
                      sideToCenterGap: sideToCenterGap,
                      sharedOpponentSize: sharedOpponentSize,
                      tw: tw,
                      handPadding: handPadding,
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  SizedBox(
                    height: topHeight,
                    child: Padding(
                      padding: topPadding,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: sharedOpponentSize,
                            maxHeight: sharedOpponentSize,
                          ),
                          child: topOpponent,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: boardGap),
                  Expanded(
                    child: _buildLandscapeLayout(
                      sidePad: sidePad,
                      topToMiddleGap: topToMiddleGap,
                      sideToCenterGap: sideToCenterGap,
                      sharedOpponentSize: sharedOpponentSize,
                      tw: tw,
                      trickToHandGap: trickToHandGap,
                      handPadding: handPadding,
                    ),
                  ),
                  actionBar,
                ],
              ),
      );
    },
  );

  /// Portrait mobile: all sections content-sized, space distributed evenly.
  Widget _buildPortraitLayout({
    required final double sidePad,
    required final double sideToCenterGap,
    required final double sharedOpponentSize,
    required final double tw,
    required final EdgeInsets handPadding,
  }) => LayoutBuilder(
    builder: (final context, final constraints) {
      final areaWidth = math.max<double>(
        0,
        constraints.maxWidth - (sidePad * 2),
      );
      final centerMaxWidth = math.max<double>(
        0,
        areaWidth - (sharedOpponentSize * 2) - (sideToCenterGap * 2),
      );
      final centerScale = 1.08 + 0.14 * tw;
      // Trick size from width, capped to avoid being too tall.
      final trickSize = math.min(
        constraints.maxHeight * 0.35,
        math.max(sharedOpponentSize * centerScale, centerMaxWidth),
      );

      return Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Middle row: opponents + trick square.
          Padding(
            padding: EdgeInsets.symmetric(horizontal: sidePad),
            child: SizedBox(
              height: math.max(sharedOpponentSize, trickSize),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: sharedOpponentSize,
                    height: sharedOpponentSize,
                    child: leftOpponent,
                  ),
                  SizedBox(width: sideToCenterGap),
                  SizedBox(
                    width: trickSize,
                    height: trickSize,
                    child: trickArea,
                  ),
                  SizedBox(width: sideToCenterGap),
                  SizedBox(
                    width: sharedOpponentSize,
                    height: sharedOpponentSize,
                    child: rightOpponent,
                  ),
                ],
              ),
            ),
          ),
          // Hand + action bar grouped together, no gap between them.
          Padding(
            padding: handPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [handArea, actionBar],
            ),
          ),
        ],
      );
    },
  );

  /// Landscape / desktop: traditional flex-based split.
  Widget _buildLandscapeLayout({
    required final double sidePad,
    required final double topToMiddleGap,
    required final double sideToCenterGap,
    required final double sharedOpponentSize,
    required final double tw,
    required final double trickToHandGap,
    required final EdgeInsets handPadding,
  }) => Column(
    children: [
      Expanded(
        flex: 6,
        child: Padding(
          padding: EdgeInsets.fromLTRB(sidePad, topToMiddleGap, sidePad, 0),
          child: LayoutBuilder(
            builder: (final context, final areaConstraints) {
              final areaWidth = areaConstraints.maxWidth;
              final areaHeight = areaConstraints.maxHeight;
              final centerMaxWidth = math.max<double>(
                0,
                areaWidth - (sharedOpponentSize * 2) - (sideToCenterGap * 2),
              );
              final opponentSquareSize = math.max<double>(
                0,
                math.min(areaHeight, sharedOpponentSize),
              );
              final centerScale = 1.08 + 0.14 * tw;
              final centerSquareSize = math.max<double>(
                0,
                math.min(
                  areaHeight,
                  math.max(opponentSquareSize * centerScale, centerMaxWidth),
                ),
              );

              return SizedBox(
                height: math.max(opponentSquareSize, centerSquareSize),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: opponentSquareSize,
                      height: opponentSquareSize,
                      child: leftOpponent,
                    ),
                    SizedBox(width: sideToCenterGap),
                    SizedBox(
                      width: centerSquareSize,
                      height: centerSquareSize,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: centerSquareSize,
                            maxHeight: centerSquareSize,
                          ),
                          child: trickArea,
                        ),
                      ),
                    ),
                    SizedBox(width: sideToCenterGap),
                    SizedBox(
                      width: opponentSquareSize,
                      height: opponentSquareSize,
                      child: rightOpponent,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      SizedBox(height: trickToHandGap),
      Expanded(
        flex: 5,
        child: Padding(padding: handPadding, child: handArea),
      ),
    ],
  );
}
