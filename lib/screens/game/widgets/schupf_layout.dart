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

SchupfLayout computeSchupfLayout({
  required final double? maxHeight,
  final bool hasHeader = true,
}) {
  // Precise overhead for all fixed-height items in the selection Column:
  //   header + gap:       hasHeader ? ~38  : 0
  //   title:              ~22
  //   title→targets gap:  tightGap + looseGap (estimated ~8)
  //   target labels:      ~16
  //   target label→box gap: tightGap (~3)
  //   target box insets:  2 * 8 = 16
  //   targets→button gap: tightGap (~3)
  //   button:             ~40
  //   button→hand gap:    tightGap (~3)
  // Total ≈ 111 (with header) or 73 (without header)
  final headerOverhead = hasHeader ? 38.0 : 0.0;
  const targetInset = 8.0;
  const targetInsetTotal = targetInset * 2; // 16
  const nonCardOverhead =
      22 +
      8 +
      16 +
      3 +
      3 +
      40 +
      3 +
      16.0; // 111 (incl labels+inset+gaps+button+margin)
  final fixedOverhead = headerOverhead + nonCardOverhead + targetInsetTotal;

  // Budget remaining for actual card images (target card + hand cards).
  final budgetForCards = maxHeight == null
      ? CardWidget.compactHeight * 0.75 + 96.0
      : (maxHeight - fixedOverhead).clamp(30.0, 280.0);

  // Split closer to even so both target and hand cards remain readable.
  final targetCardBudget = budgetForCards * 0.5;
  final handBudget = budgetForCards * 0.5;

  final maxTargetCardHeight = targetCardBudget.clamp(
    32.0,
    CardWidget.compactHeight * 0.85,
  );
  final cardScale = (maxTargetCardHeight / CardWidget.compactHeight).clamp(
    0.28,
    1.0,
  );
  final targetWidth = CardWidget.compactWidth * cardScale + (targetInset * 2);
  final targetHeight = CardWidget.compactHeight * cardScale + (targetInset * 2);
  final availableHeight = handBudget.clamp(28.0, 110.0);
  final tightGap = maxHeight == null ? 4.0 : (maxHeight * 0.01).clamp(0.0, 4.0);
  final looseGap = maxHeight == null
      ? 6.0
      : (maxHeight * 0.015).clamp(0.0, 6.0);
  final rowScale = (availableHeight / CardWidget.compactHeight).clamp(
    0.28,
    1.0,
  );
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
}) => Align(
  alignment: Alignment.topCenter,
  heightFactor: 1,
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
