import 'package:flutter/material.dart' hide Card;

import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/widgets/card_widget.dart';
import 'package:tichu/widgets/overlapping_card_row.dart';

/// Layout metrics for the schupf target row and hand row.
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

// ── Shared helpers ─────────────────────────────────────────────────────

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

// ── SchupfPanel ────────────────────────────────────────────────────────

enum SchupfSlot { left, partner, right }

class SchupfPanel extends StatelessWidget {
  const SchupfPanel({
    super.key,
    required this.hand,
    required this.schupfToLeft,
    required this.schupfToPartner,
    required this.schupfToRight,
    required this.onSetSlot,
    required this.onClearSlot,
    required this.onSubmit,
    this.header,
    this.schupfCursorIndex,
    this.desktopSchupfHelperEnabled = false,
  });

  final List<Card> hand;
  final Card? schupfToLeft;
  final Card? schupfToPartner;
  final Card? schupfToRight;
  final void Function(SchupfSlot slot, Card card) onSetSlot;
  final void Function(SchupfSlot slot) onClearSlot;
  final VoidCallback? onSubmit;
  final Widget? header;
  final int? schupfCursorIndex;
  final bool desktopSchupfHelperEnabled;

  @override
  Widget build(final BuildContext context) {
    final canSubmit =
        schupfToLeft != null &&
        schupfToPartner != null &&
        schupfToRight != null;
    final selectedCards = <Card>{
      ...[schupfToLeft, schupfToPartner, schupfToRight].whereType<Card>(),
    };
    final available = hand
        .where((final card) => !selectedCards.contains(card))
        .toList();

    return LayoutBuilder(
      builder: (final context, final constraints) {
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : null;
        final layout = computeSchupfLayout(maxHeight: maxHeight);
        final overlapCount = available.length > 1 ? available.length - 1 : 0;
        final handNaturalWidth =
            layout.rowCardWidth +
            overlapCount * (layout.rowCardWidth + layout.rowSpacing);
        final contentWidth = layout.targetRowWidth > handNaturalWidth
            ? layout.targetRowWidth
            : handNaturalWidth;
        final panelWidth = constraints.maxWidth.isFinite
            ? (contentWidth + 24).clamp(0.0, constraints.maxWidth)
            : contentWidth + 24;

        Widget buildTarget({
          required final String label,
          required final Card? value,
          required final VoidCallback onRemove,
          required final ValueChanged<Card> onAccept,
        }) => DragTarget<Card>(
          onAcceptWithDetails: (final details) => onAccept(details.data),
          builder: (final context, final candidateData, final rejectedData) {
            final isActive = candidateData.isNotEmpty;
            return SchupfTargetBox(
              label: label,
              targetWidth: layout.targetWidth,
              targetHeight: layout.targetHeight,
              labelGap: layout.tightGap,
              content: value == null
                  ? const Icon(
                      Icons.add_circle_outline,
                      color: Colors.white38,
                      size: 26,
                    )
                  : CardWidget(
                      card: value,
                      isSelected: false,
                      compact: true,
                      scale: layout.cardScale,
                    ),
              onTap: value == null ? null : onRemove,
              isActive: isActive,
            );
          },
        );

        final content = Column(
          children: [
            if (header != null) ...[header!, SizedBox(height: layout.tightGap)],
            Text(
              'Schupf your cards',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: layout.tightGap + layout.looseGap),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                buildTarget(
                  label: 'Left',
                  value: schupfToRight,
                  onRemove: () => onClearSlot(SchupfSlot.right),
                  onAccept: (final card) => onSetSlot(SchupfSlot.right, card),
                ),
                const SizedBox(width: 12),
                buildTarget(
                  label: 'Partner',
                  value: schupfToPartner,
                  onRemove: () => onClearSlot(SchupfSlot.partner),
                  onAccept: (final card) => onSetSlot(SchupfSlot.partner, card),
                ),
                const SizedBox(width: 12),
                buildTarget(
                  label: 'Right',
                  value: schupfToLeft,
                  onRemove: () => onClearSlot(SchupfSlot.left),
                  onAccept: (final card) => onSetSlot(SchupfSlot.left, card),
                ),
              ],
            ),
            SizedBox(height: layout.tightGap),
            Center(
              child: ElevatedButton.icon(
                onPressed: canSubmit ? onSubmit : null,
                icon: const Icon(Icons.swap_horiz),
                style: ElevatedButton.styleFrom(
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    width: 0.6,
                  ),
                ),
                label: const Text('Schupf'),
              ),
            ),
            SizedBox(height: layout.tightGap),
            SizedBox(
              height: layout.availableHeight,
              child: SizedBox(
                width: contentWidth,
                child: OverlappingCardRow(
                  itemCount: available.length,
                  cardWidth: layout.rowCardWidth,
                  cardHeight: layout.rowCardHeight,
                  spacing: layout.rowSpacing,
                  minVisible: 14 * layout.rowScale,
                  height: layout.rowCardHeight + 8,
                  itemBuilder: (final context, final index) {
                    final card = available[index];
                    void onQuickAssign() {
                      if (!desktopSchupfHelperEnabled) return;
                      if (schupfToRight == null) {
                        onSetSlot(SchupfSlot.right, card);
                      } else if (schupfToPartner == null) {
                        onSetSlot(SchupfSlot.partner, card);
                      } else if (schupfToLeft == null) {
                        onSetSlot(SchupfSlot.left, card);
                      }
                    }

                    final isCursor = schupfCursorIndex == index;

                    Widget buildCard() => GestureDetector(
                      onDoubleTap: onQuickAssign,
                      child: CardWidget(
                        card: card,
                        isSelected: isCursor,
                        compact: true,
                        scale: layout.rowScale,
                      ),
                    );

                    return Draggable<Card>(
                      data: card,
                      feedback: Material(
                        color: Colors.transparent,
                        child: CardWidget(
                          card: card,
                          isSelected: false,
                          compact: true,
                          scale: layout.rowScale,
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.4,
                        child: buildCard(),
                      ),
                      child: buildCard(),
                    );
                  },
                ),
              ),
            ),
          ],
        );

        return buildSchupfPanelContainer(
          panelWidth: panelWidth,
          child: maxHeight == null
              ? content
              : SizedBox(height: maxHeight, child: content),
        );
      },
    );
  }
}

// ── SchupfReceiptPanel ─────────────────────────────────────────────────

class SchupfReceiptPanel extends StatelessWidget {
  const SchupfReceiptPanel({
    super.key,
    required this.hand,
    required this.schupfSentCards,
    required this.receipts,
    required this.onAcknowledge,
    required this.schupfAckPending,
    this.header,
  });

  final List<Card> hand;
  final List<Card> schupfSentCards;
  final List<SchupfReceipt> receipts;
  final VoidCallback onAcknowledge;
  final bool schupfAckPending;
  final Widget? header;

  @override
  Widget build(final BuildContext context) {
    final receiptByDirection = {
      for (final receipt in receipts) receipt.direction: receipt,
    };

    return LayoutBuilder(
      builder: (final context, final constraints) {
        final maxH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : null;
        final layout = computeSchupfLayout(maxHeight: maxH);
        final filteredHand = <Card>[];
        final hiddenCards = List<Card>.from(schupfSentCards);
        for (final card in hand) {
          final hiddenIndex = hiddenCards.indexOf(card);
          if (hiddenIndex >= 0) {
            hiddenCards.removeAt(hiddenIndex);
          } else {
            filteredHand.add(card);
          }
        }
        final overlapCount = filteredHand.length > 1
            ? filteredHand.length - 1
            : 0;
        final handNaturalWidth =
            layout.rowCardWidth +
            overlapCount * (layout.rowCardWidth + layout.rowSpacing);
        final contentWidth = layout.targetRowWidth > handNaturalWidth
            ? layout.targetRowWidth
            : handNaturalWidth;
        final panelWidth = constraints.maxWidth.isFinite
            ? (contentWidth + 24).clamp(0.0, constraints.maxWidth)
            : contentWidth + 24;

        Widget buildTarget({
          required final String label,
          required final SchupfReceipt? receipt,
        }) => SchupfTargetBox(
          label: label,
          targetWidth: layout.targetWidth,
          targetHeight: layout.targetHeight,
          labelGap: layout.tightGap,
          content: receipt == null
              ? const Icon(
                  Icons.hourglass_empty,
                  color: Colors.white38,
                  size: 24,
                )
              : CardWidget(
                  card: receipt.card,
                  isSelected: false,
                  compact: true,
                  scale: layout.cardScale,
                ),
        );

        final content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (header != null) ...[header!, SizedBox(height: layout.tightGap)],
            Text(
              'Schupf received',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                buildTarget(
                  label: 'Left',
                  receipt: receiptByDirection[SchupfDirection.right],
                ),
                const SizedBox(width: 12),
                buildTarget(
                  label: 'Partner',
                  receipt: receiptByDirection[SchupfDirection.partner],
                ),
                const SizedBox(width: 12),
                buildTarget(
                  label: 'Right',
                  receipt: receiptByDirection[SchupfDirection.left],
                ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: schupfAckPending ? null : onAcknowledge,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('PLAY'),
            ),
            SizedBox(height: layout.tightGap),
            if (filteredHand.isNotEmpty)
              SizedBox(
                height: layout.availableHeight,
                width: contentWidth,
                child: OverlappingCardRow(
                  itemCount: filteredHand.length,
                  cardWidth: layout.rowCardWidth,
                  cardHeight: layout.rowCardHeight,
                  spacing: layout.rowSpacing,
                  minVisible: 14 * layout.rowScale,
                  height: layout.rowCardHeight + 8,
                  itemBuilder: (final context, final index) => CardWidget(
                    card: filteredHand[index],
                    isSelected: false,
                    compact: true,
                    scale: layout.rowScale,
                  ),
                ),
              ),
          ],
        );

        return buildSchupfPanelContainer(
          panelWidth: panelWidth,
          child: content,
        );
      },
    );
  }
}
