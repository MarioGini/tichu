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
      final isWide = constraints.maxWidth > 720;
      final isCompact = constraints.maxHeight < 500;
      final isPortraitMobile =
          constraints.maxHeight > constraints.maxWidth &&
          constraints.maxWidth < 600;

      /// Unified gap used between all board sections
      /// (top↔middle, sides↔trick, middle↔hand).
      final boardGap = isCompact ? 4.0 : (isWide ? 12.0 : 8.0);
      final topPadding = isCompact
          ? const EdgeInsets.fromLTRB(8, 4, 8, 0)
          : const EdgeInsets.fromLTRB(16, 8, 16, 0);
      final sidePad = isCompact ? 4.0 : 8.0;
      final handPadding = isCompact
          ? const EdgeInsets.fromLTRB(8, 0, 8, 2)
          : const EdgeInsets.fromLTRB(12, 0, 12, 6);
      final trickToHandGap = isPortraitMobile ? 2.0 : (isCompact ? 4.0 : 6.0);
      final sideToCenterGap = isCompact ? 12.0 : (isWide ? 30.0 : 22.0);
      final areaWidth = math.max<double>(
        0,
        constraints.maxWidth - (sidePad * 2),
      );
      final maxSideWidth = math.min(
        areaWidth * (isWide ? 0.18 : 0.22),
        isWide ? 240.0 : (isCompact ? 142.0 : 186.0),
      );
      final sideWidth = math.max<double>(
        0,
        math.min(maxSideWidth, (areaWidth - sideToCenterGap * 2) / 3),
      );
      final sharedOpponentSize = math.min(
        sideWidth,
        constraints.maxHeight * (isCompact ? 0.17 : 0.23),
      );
      const topPendingGap = 6.0;
      final topPendingLaneHeight = (sharedOpponentSize * 0.28).clamp(
        34.0,
        64.0,
      );
      final topToMiddleGap = topPendingGap + topPendingLaneHeight;
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
        child: Column(
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
              child: Column(
                children: [
                  Expanded(
                    flex: isPortraitMobile ? 6 : (isCompact ? 7 : 6),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        sidePad,
                        topToMiddleGap,
                        sidePad,
                        0,
                      ),
                      child: LayoutBuilder(
                        builder: (final context, final areaConstraints) {
                          final areaWidth = areaConstraints.maxWidth;
                          final areaHeight = areaConstraints.maxHeight;
                          final centerMaxWidth = math.max<double>(
                            0,
                            areaWidth -
                                (sharedOpponentSize * 2) -
                                (sideToCenterGap * 2),
                          );
                          final opponentSquareSize = math.max<double>(
                            0,
                            math.min(areaHeight, sharedOpponentSize),
                          );
                          final centerSquareSize = math.max<double>(
                            0,
                            math.min(
                              areaHeight,
                              math.max(
                                opponentSquareSize * (isWide ? 1.22 : 1.08),
                                centerMaxWidth,
                              ),
                            ),
                          );

                          return SizedBox(
                            height: math.max(
                              opponentSquareSize,
                              centerSquareSize,
                            ),
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
                    flex: isPortraitMobile ? 5 : (isCompact ? 4 : 5),
                    child: Padding(
                      padding: handPadding,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: handArea,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actionBar,
          ],
        ),
      );
    },
  );
}
