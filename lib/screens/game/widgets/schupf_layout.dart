import 'package:flutter/material.dart';

import 'package:tichu/widgets/card_widget.dart';

/// Layout metrics shared by the schupf selection and receipt panels.
typedef SchupfLayout = ({
  double cardScale,
  double targetWidth,
  double targetHeight,
  double availableHeight,
  double tightGap,
  double looseGap,
  double rowScale,
  double rowCardWidth,
  double rowCardHeight,
  double rowSpacing,
  double targetRowWidth,
});

SchupfLayout computeSchupfLayout({required final double? maxHeight}) {
  const minCardHeight = 90.0;
  final maxTargetHeight = maxHeight == null
      ? CardWidget.compactHeight * 0.75
      : (maxHeight * 0.22).clamp(
          minCardHeight,
          CardWidget.compactHeight * 0.75,
        );
  const minScale = minCardHeight / CardWidget.compactHeight;
  final cardScale = (maxTargetHeight / CardWidget.compactHeight).clamp(
    minScale,
    0.9,
  );
  const targetInset = 8.0;
  final targetWidth = CardWidget.compactWidth * cardScale + (targetInset * 2);
  final targetHeight = CardWidget.compactHeight * cardScale + (targetInset * 2);
  final availableHeight = maxHeight == null
      ? 96.0
      : (maxHeight * 0.18).clamp(48.0, 96.0);
  final tightGap = maxHeight == null ? 4.0 : (maxHeight * 0.01).clamp(0.0, 4.0);
  final looseGap = maxHeight == null
      ? 6.0
      : (maxHeight * 0.015).clamp(0.0, 6.0);
  final rowScale = (availableHeight / CardWidget.compactHeight).clamp(0.5, 0.9);
  final rowCardWidth = CardWidget.compactWidth * rowScale;
  final rowCardHeight = CardWidget.compactHeight * rowScale;
  final rowSpacing = 6 * rowScale;
  final targetRowWidth = (targetWidth * 3) + 24;

  return (
    cardScale: cardScale,
    targetWidth: targetWidth,
    targetHeight: targetHeight,
    availableHeight: availableHeight,
    tightGap: tightGap,
    looseGap: looseGap,
    rowScale: rowScale,
    rowCardWidth: rowCardWidth,
    rowCardHeight: rowCardHeight,
    rowSpacing: rowSpacing,
    targetRowWidth: targetRowWidth,
  );
}

/// Shared container decoration for schupf panels.
Widget buildSchupfPanelContainer({
  required final double panelWidth,
  required final Widget child,
}) => Center(
  child: SizedBox(
    width: panelWidth,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: child,
    ),
  ),
);

/// Target box used by both schupf selection and receipt panels.
class SchupfTargetBox extends StatelessWidget {
  const SchupfTargetBox({
    super.key,
    required this.label,
    required this.targetWidth,
    required this.targetHeight,
    required this.content,
    this.isActive = false,
    this.labelGap = 4,
    this.onTap,
    this.targetInset = 8,
  });

  final String label;
  final double targetWidth;
  final double targetHeight;
  final Widget content;
  final bool isActive;
  final double labelGap;
  final VoidCallback? onTap;
  final double targetInset;

  @override
  Widget build(final BuildContext context) => SizedBox(
    width: targetWidth,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: Colors.white70),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: labelGap),
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: targetWidth,
            height: targetHeight,
            padding: EdgeInsets.all(targetInset),
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.amber.withValues(alpha: 0.15)
                  : Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive ? Colors.amber : Colors.white24,
              ),
            ),
            clipBehavior: Clip.hardEdge,
            child: Center(child: content),
          ),
        ),
      ],
    ),
  );
}

/// Which schupf slot a card is assigned to.
enum SchupfSlot { left, partner, right }
