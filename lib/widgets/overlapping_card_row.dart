import 'dart:math' as math;

import 'package:flutter/material.dart';

class OverlappingCardRow extends StatelessWidget {
  const OverlappingCardRow({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.cardWidth,
    required this.cardHeight,
    this.spacing = 0,
    this.minVisible = 18,
    this.height,
    this.center = true,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double cardWidth;
  final double cardHeight;
  final double spacing;
  final double minVisible;
  final double? height;
  final bool center;

  @override
  Widget build(final BuildContext context) {
    final contentHeight = height ?? cardHeight;

    if (itemCount == 0) {
      return SizedBox(height: contentHeight);
    }

    return LayoutBuilder(
      builder: (final context, final constraints) {
        final availWidth = constraints.maxWidth;
        if (itemCount == 1) {
          final child = itemBuilder(context, 0);
          if (!availWidth.isFinite || cardWidth <= availWidth) {
            return SizedBox(
              height: contentHeight,
              child: Align(
                alignment: center ? Alignment.center : Alignment.centerLeft,
                child: child,
              ),
            );
          }

          final widthScale = (availWidth / cardWidth).clamp(0.0, 1.0);
          return SizedBox(
            height: contentHeight,
            width: availWidth,
            child: Align(
              alignment: center ? Alignment.center : Alignment.centerLeft,
              child: Transform.scale(scale: widthScale, child: child),
            ),
          );
        }

        final naturalStep = cardWidth + spacing;
        final totalNatural =
            cardWidth + math.max(0, itemCount - 1) * naturalStep;

        if (totalNatural <= availWidth) {
          return SizedBox(
            height: contentHeight,
            child: Row(
              mainAxisAlignment: center
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < itemCount; i++) ...[
                  itemBuilder(context, i),
                  if (i < itemCount - 1) SizedBox(width: spacing),
                ],
              ],
            ),
          );
        }

        final step = math.max(
          minVisible,
          (availWidth - cardWidth) / math.max(1, itemCount - 1),
        );

        return SizedBox(
          height: contentHeight,
          width: availWidth,
          child: Stack(
            children: [
              for (int i = 0; i < itemCount; i++)
                Positioned(
                  left: i * step,
                  top: 0,
                  child: itemBuilder(context, i),
                ),
            ],
          ),
        );
      },
    );
  }
}
