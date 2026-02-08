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
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 720;
        final topHeight = (constraints.maxHeight * 0.24)
            .clamp(isWide ? 130.0 : 112.0, isWide ? 200.0 : 170.0)
            .toDouble();
        final topMaxWidth = math.min(
          constraints.maxWidth * (isWide ? 0.7 : 0.8),
          isWide ? 600.0 : 480.0,
        );
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
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: LayoutBuilder(
                    builder: (context, areaConstraints) {
                      final areaWidth = areaConstraints.maxWidth;
                      final areaHeight = areaConstraints.maxHeight;
                      final gap = isWide ? 12.0 : 8.0;
                      final maxSideWidth = math.min(
                        areaWidth * (isWide ? 0.24 : 0.28),
                        isWide ? 260.0 : 200.0,
                      );
                      final sideWidth = math.max(
                        0.0,
                        math.min(maxSideWidth, (areaWidth - gap * 2) / 3),
                      );
                      final centerMaxWidth = math.max(
                        0.0,
                        areaWidth - (sideWidth * 2) - (gap * 2),
                      );
                      final squareSize = math.max(
                        0.0,
                        math.min(areaHeight, centerMaxWidth),
                      );
                      final sideHeight = math.min(areaHeight, squareSize);

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: sideWidth,
                            height: sideHeight,
                            child: leftOpponent,
                          ),
                          SizedBox(width: gap),
                          SizedBox(
                            width: squareSize,
                            height: squareSize,
                            child: trickArea,
                          ),
                          SizedBox(width: gap),
                          SizedBox(
                            width: sideWidth,
                            height: sideHeight,
                            child: rightOpponent,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: handArea,
              ),
              actionBar,
            ],
          ),
        );
      },
    );
  }
}
