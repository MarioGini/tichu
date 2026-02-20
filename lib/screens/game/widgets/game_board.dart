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
        final topMaxWidth = math.min(
          constraints.maxWidth * (isWide ? 0.7 : 0.8),
          isWide ? 600.0 : 480.0,
        );
        final desiredTopHeight = isCompact
            ? (constraints.maxHeight * 0.2).clamp(64.0, 108.0)
            : (constraints.maxHeight * 0.3).clamp(
                isWide ? 160.0 : 136.0,
                isWide ? 240.0 : 200.0,
              );
        final topHeight = math.min(desiredTopHeight, topMaxWidth);

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
                        maxWidth: topMaxWidth,
                        minHeight: topHeight - 20,
                      ),
                      child: topOpponent,
                    ),
                  ),
                ),
              ),
              SizedBox(height: boardGap),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: sidePad),
                child: LayoutBuilder(
                  builder: (final context, final areaConstraints) {
                    final areaWidth = areaConstraints.maxWidth;
                    final areaHeight = areaConstraints.maxHeight;
                    final maxSideWidth = math.min(
                      areaWidth * (isWide ? 0.24 : 0.28),
                      isWide ? 260.0 : (isCompact ? 160.0 : 200.0),
                    );
                    final sideWidth = math.max<double>(
                      0,
                      math.min(maxSideWidth, (areaWidth - boardGap * 2) / 3),
                    );
                    final centerMaxWidth = math.max<double>(
                      0,
                      areaWidth - (sideWidth * 2) - (boardGap * 2),
                    );
                    final squareSize = math.max<double>(
                      0,
                      math.min(
                            areaHeight,
                            math.min(sideWidth, centerMaxWidth),
                          ) *
                          0.94,
                    );

                    return SizedBox(
                      height: squareSize,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: squareSize,
                            height: squareSize,
                            child: leftOpponent,
                          ),
                          SizedBox(width: boardGap),
                          SizedBox(
                            width: squareSize,
                            height: squareSize,
                            child: trickArea,
                          ),
                          SizedBox(width: boardGap),
                          SizedBox(
                            width: squareSize,
                            height: squareSize,
                            child: rightOpponent,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: boardGap),
              Flexible(
                child: Padding(padding: handPadding, child: handArea),
              ),
              actionBar,
            ],
          ),
        );
      },
    );
}
