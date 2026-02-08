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
  Widget build(BuildContext context) {
    final contentHeight = height ?? cardHeight;

    if (itemCount == 0) {
      return SizedBox(height: contentHeight);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availWidth = constraints.maxWidth;
        final naturalStep = cardWidth + spacing;
        final totalNatural = itemCount * naturalStep;

        if (totalNatural <= availWidth) {
          return SizedBox(
            height: contentHeight,
            child: Row(
              mainAxisAlignment: center
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < itemCount; i++) itemBuilder(context, i),
              ],
            ),
          );
        }

        final step = math.max(
          minVisible,
          (availWidth - cardWidth - spacing) / math.max(1, itemCount - 1),
        );

        return SizedBox(
          height: contentHeight,
          child: Stack(
            clipBehavior: Clip.none,
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
