import 'dart:math' as math;

import 'package:material_ui/material_ui.dart' hide Card;

import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/screens/game/widgets/schupf_layout.dart';
import 'package:tichu/widgets/card_widget.dart';
import 'package:tichu/widgets/overlapping_card_row.dart';

// ── Mode sealed hierarchy ──────────────────────────────────────────────

/// Determines whether the panel shows the selection UI or receipt UI.
sealed class SchupfPanelMode {
  const SchupfPanelMode();
}

/// Selection mode: the player picks cards to schupf.
class SchupfSelectionMode extends SchupfPanelMode {
  const SchupfSelectionMode({
    required this.schupfToLeft,
    required this.schupfToPartner,
    required this.schupfToRight,
    required this.onSetSlot,
    required this.onClearSlot,
    required this.onSubmit,
    this.schupfCursorIndex,
  });

  final Card? schupfToLeft;
  final Card? schupfToPartner;
  final Card? schupfToRight;
  final void Function(SchupfSlot slot, Card card) onSetSlot;
  final void Function(SchupfSlot slot) onClearSlot;
  final VoidCallback? onSubmit;
  final int? schupfCursorIndex;
}

/// Receipt mode: the player views received cards and acknowledges.
class SchupfReceiptMode extends SchupfPanelMode {
  const SchupfReceiptMode({
    required this.schupfSentCards,
    required this.receipts,
    required this.onAcknowledge,
    required this.schupfAckPending,
  });

  final List<Card> schupfSentCards;
  final List<SchupfReceipt> receipts;
  final VoidCallback onAcknowledge;
  final bool schupfAckPending;
}

// ── SchupfPanel ────────────────────────────────────────────────────────

/// Unified schupf panel for both card selection and receipt display.
class SchupfPanel extends StatelessWidget {
  const SchupfPanel({
    super.key,
    required this.hand,
    required this.mode,
    this.header,
  });

  final List<Card> hand;
  final SchupfPanelMode mode;
  final Widget? header;

  /// Vertical padding consumed by the container in [buildSchupfPanelContainer].
  static const double _containerPadding = 24; // 12 top + 12 bottom

  @override
  Widget build(final BuildContext context) => LayoutBuilder(
    builder: (final context, final constraints) {
      final totalHeight = constraints.maxHeight.isFinite
          ? constraints.maxHeight
          : null;
      // Subtract container padding so layout is computed for inner content.
      final contentHeight = totalHeight == null
          ? null
          : (totalHeight - _containerPadding).clamp(0.0, double.infinity);
      final compact =
          totalHeight != null &&
          totalHeight < 330 &&
          constraints.maxWidth > totalHeight * 1.5;
      final layout = computeSchupfLayout(
        maxHeight: contentHeight,
        hasHeader: header != null && !compact,
        compact: compact,
      );

      return switch (mode) {
        final SchupfSelectionMode m => _buildSelection(
          context,
          constraints,
          layout,
          m,
          compact: compact,
        ),
        final SchupfReceiptMode m => _buildReceipt(
          context,
          constraints,
          layout,
          m,
          compact: compact,
        ),
      };
    },
  );

  // ── Selection mode ─────────────────────────────────────────────────

  Widget _buildSelection(
    final BuildContext context,
    final BoxConstraints constraints,
    final SchupfLayout layout,
    final SchupfSelectionMode m, {
    required final bool compact,
  }) {
    final canSubmit =
        m.schupfToLeft != null &&
        m.schupfToPartner != null &&
        m.schupfToRight != null;
    final selectedCards = <Card>{
      ...[m.schupfToLeft, m.schupfToPartner, m.schupfToRight].whereType<Card>(),
    };
    final available = hand
        .where((final card) => !selectedCards.contains(card))
        .toList();
    final panelWidth = _panelWidth(constraints, layout, available.length);
    final contentMaxWidth = constraints.maxWidth.isFinite
        ? panelWidth - _containerPadding < 0
              ? 0.0
              : panelWidth - _containerPadding
        : _contentWidth(layout, available.length);

    Widget buildTarget({
      required final String label,
      required final Card? value,
      required final VoidCallback onRemove,
      required final ValueChanged<Card> onAccept,
    }) => DragTarget<Card>(
      onAcceptWithDetails: (final details) => onAccept(details.data),
      builder: (final context, final candidateData, final rejectedData) =>
          SchupfTargetBox(
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
            isActive: candidateData.isNotEmpty,
          ),
    );

    final handRow = _handRow(layout, available, m, maxWidth: contentMaxWidth);

    final targets = [
      buildTarget(
        label: 'Left',
        value: m.schupfToRight,
        onRemove: () => m.onClearSlot(SchupfSlot.right),
        onAccept: (final card) => m.onSetSlot(SchupfSlot.right, card),
      ),
      buildTarget(
        label: 'Partner',
        value: m.schupfToPartner,
        onRemove: () => m.onClearSlot(SchupfSlot.partner),
        onAccept: (final card) => m.onSetSlot(SchupfSlot.partner, card),
      ),
      buildTarget(
        label: 'Right',
        value: m.schupfToLeft,
        onRemove: () => m.onClearSlot(SchupfSlot.left),
        onAccept: (final card) => m.onSetSlot(SchupfSlot.left, card),
      ),
    ];
    final schupfButton = ElevatedButton.icon(
      onPressed: canSubmit ? m.onSubmit : null,
      icon: const Icon(Icons.swap_horiz),
      style: ElevatedButton.styleFrom(
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.6,
        ),
      ),
      label: const Text('Schupf'),
    );

    final fixedChildren = compact
        ? [
            _compactTopRow(
              context,
              title: 'Schupf your cards',
              hint: 'Tap cards to pass them',
              targets: targets,
              button: schupfButton,
              maxWidth: contentMaxWidth,
            ),
            SizedBox(height: layout.tightGap + 2),
          ]
        : [
            if (header != null) ...[header!, SizedBox(height: layout.tightGap)],
            _title(context, 'Schupf your cards'),
            SizedBox(height: layout.tightGap + layout.looseGap),
            _targetRow(targets, maxWidth: contentMaxWidth),
            SizedBox(height: layout.tightGap),
            Center(child: schupfButton),
            SizedBox(height: layout.tightGap),
          ];

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...fixedChildren,
        ClipRect(
          child: Align(alignment: Alignment.topCenter, child: handRow),
        ),
      ],
    );

    return buildSchupfPanelContainer(panelWidth: panelWidth, child: content);
  }

  Widget _handRow(
    final SchupfLayout layout,
    final List<Card> available,
    final SchupfSelectionMode m, {
    required final double maxWidth,
  }) => SizedBox(
    width: math.min(_contentWidth(layout, available.length), maxWidth),
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
          if (m.schupfToRight == null) {
            m.onSetSlot(SchupfSlot.right, card);
          } else if (m.schupfToPartner == null) {
            m.onSetSlot(SchupfSlot.partner, card);
          } else if (m.schupfToLeft == null) {
            m.onSetSlot(SchupfSlot.left, card);
          }
        }

        final isCursor = m.schupfCursorIndex == index;

        // A single tap moves the card into the next free slot; dragging
        // onto a specific slot still works.
        Widget buildCard() => GestureDetector(
          onTap: onQuickAssign,
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
          childWhenDragging: Opacity(opacity: 0.4, child: buildCard()),
          child: buildCard(),
        );
      },
    ),
  );

  // ── Receipt mode ───────────────────────────────────────────────────

  Widget _buildReceipt(
    final BuildContext context,
    final BoxConstraints constraints,
    final SchupfLayout layout,
    final SchupfReceiptMode m, {
    required final bool compact,
  }) {
    final receiptByDirection = {
      for (final receipt in m.receipts) receipt.direction: receipt,
    };
    final filteredHand = <Card>[];
    final hiddenCards = List<Card>.from(m.schupfSentCards)
      ..addAll(m.receipts.map((final receipt) => receipt.card));
    for (final card in hand) {
      final hiddenIndex = hiddenCards.indexOf(card);
      if (hiddenIndex >= 0) {
        hiddenCards.removeAt(hiddenIndex);
      } else {
        filteredHand.add(card);
      }
    }
    final panelWidth = _panelWidth(constraints, layout, filteredHand.length);
    final contentMaxWidth = constraints.maxWidth.isFinite
        ? panelWidth - _containerPadding < 0
              ? 0.0
              : panelWidth - _containerPadding
        : _contentWidth(layout, filteredHand.length);

    Widget buildTarget({
      required final String label,
      required final SchupfReceipt? receipt,
    }) => SchupfTargetBox(
      label: label,
      targetWidth: layout.targetWidth,
      targetHeight: layout.targetHeight,
      labelGap: layout.tightGap,
      content: receipt == null
          ? const Icon(Icons.hourglass_empty, color: Colors.white38, size: 24)
          : CardWidget(
              card: receipt.card,
              isSelected: false,
              compact: true,
              scale: layout.cardScale,
            ),
    );

    final filteredHandRow = filteredHand.isEmpty
        ? null
        : SizedBox(
            height: layout.availableHeight,
            width: math.min(
              _contentWidth(layout, filteredHand.length),
              contentMaxWidth,
            ),
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
          );

    final receiptTargets = [
      buildTarget(
        label: 'Left',
        receipt: receiptByDirection[SchupfDirection.right],
      ),
      buildTarget(
        label: 'Partner',
        receipt: receiptByDirection[SchupfDirection.partner],
      ),
      buildTarget(
        label: 'Right',
        receipt: receiptByDirection[SchupfDirection.left],
      ),
    ];
    final playButton = ElevatedButton.icon(
      onPressed: m.schupfAckPending || m.receipts.isEmpty
          ? null
          : m.onAcknowledge,
      icon: const Icon(Icons.check_circle_outline),
      label: const Text('PLAY'),
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (compact)
          _compactTopRow(
            context,
            title: 'Schupf received',
            targets: receiptTargets,
            button: playButton,
            maxWidth: contentMaxWidth,
          )
        else ...[
          if (header != null) ...[header!, SizedBox(height: layout.tightGap)],
          _title(context, 'Schupf received'),
          const SizedBox(height: 8),
          _targetRow(receiptTargets, maxWidth: contentMaxWidth),
          const SizedBox(height: 8),
          playButton,
        ],
        if (filteredHandRow != null) SizedBox(height: layout.tightGap),
        if (filteredHandRow != null)
          ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              child: filteredHandRow,
            ),
          ),
      ],
    );

    return buildSchupfPanelContainer(panelWidth: panelWidth, child: content);
  }

  // ── Shared helpers ─────────────────────────────────────────────────

  double _contentWidth(final SchupfLayout layout, final int cardCount) {
    final overlapCount = cardCount > 1 ? cardCount - 1 : 0;
    final handNaturalWidth =
        layout.rowCardWidth +
        overlapCount * (layout.rowCardWidth + layout.rowSpacing);
    return layout.targetRowWidth > handNaturalWidth
        ? layout.targetRowWidth
        : handNaturalWidth;
  }

  double _panelWidth(
    final BoxConstraints constraints,
    final SchupfLayout layout,
    final int cardCount,
  ) {
    final contentWidth = _contentWidth(layout, cardCount);
    return constraints.maxWidth.isFinite
        ? (contentWidth + 24).clamp(0.0, constraints.maxWidth)
        : contentWidth + 24;
  }

  static Widget _title(final BuildContext context, final String text) => Text(
    text,
    style: Theme.of(context).textTheme.titleMedium?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w600,
    ),
  );

  /// Short screens: title and button next to the three slots.
  static Widget _compactTopRow(
    final BuildContext context, {
    required final String title,
    required final List<Widget> targets,
    required final Widget button,
    required final double maxWidth,
    final String? hint,
  }) => SizedBox(
    width: maxWidth,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          targets[0],
          const SizedBox(width: 10),
          targets[1],
          const SizedBox(width: 10),
          targets[2],
          const SizedBox(width: 20),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title(context, title),
              if (hint != null)
                Text(
                  hint,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: Colors.white60),
                ),
              const SizedBox(height: 8),
              button,
            ],
          ),
        ],
      ),
    ),
  );

  static Widget _targetRow(
    final List<Widget> targets, {
    final double? maxWidth,
  }) {
    final row = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        targets[0],
        const SizedBox(width: 12),
        targets[1],
        const SizedBox(width: 12),
        targets[2],
      ],
    );

    if (maxWidth == null) return row;

    return SizedBox(
      width: maxWidth,
      child: FittedBox(fit: BoxFit.scaleDown, child: row),
    );
  }
}
