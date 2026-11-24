import 'dart:math' as math;

import 'package:material_ui/material_ui.dart' hide Card;

import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/screens/game/widgets/schupf_layout.dart';
import 'package:tichu/widgets/card_widget.dart';
import 'package:tichu/widgets/overlapping_card_row.dart';

part 'schupf_panel_helpers.dart';
part 'schupf_receipt_view.dart';

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

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
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
    BuildContext context,
    BoxConstraints constraints,
    SchupfLayout layout,
    SchupfSelectionMode m, {
    required bool compact,
  }) {
    final canSubmit =
        m.schupfToLeft != null &&
        m.schupfToPartner != null &&
        m.schupfToRight != null;
    final selectedCards = <Card>{
      ...[m.schupfToLeft, m.schupfToPartner, m.schupfToRight].whereType<Card>(),
    };
    final available = hand
        .where((card) => !selectedCards.contains(card))
        .toList();
    final panelWidth = _panelWidth(constraints, layout, available.length);
    final contentMaxWidth = constraints.maxWidth.isFinite
        ? panelWidth - _containerPadding < 0
              ? 0.0
              : panelWidth - _containerPadding
        : _contentWidth(layout, available.length);

    Widget buildTarget({
      required String label,
      required Card? value,
      required VoidCallback onRemove,
      required ValueChanged<Card> onAccept,
    }) => DragTarget<Card>(
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidateData, rejectedData) => SchupfTargetBox(
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
        onAccept: (card) => m.onSetSlot(SchupfSlot.right, card),
      ),
      buildTarget(
        label: 'Partner',
        value: m.schupfToPartner,
        onRemove: () => m.onClearSlot(SchupfSlot.partner),
        onAccept: (card) => m.onSetSlot(SchupfSlot.partner, card),
      ),
      buildTarget(
        label: 'Right',
        value: m.schupfToLeft,
        onRemove: () => m.onClearSlot(SchupfSlot.left),
        onAccept: (card) => m.onSetSlot(SchupfSlot.left, card),
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
    SchupfLayout layout,
    List<Card> available,
    SchupfSelectionMode m, {
    required double maxWidth,
  }) => SizedBox(
    width: math.min(_contentWidth(layout, available.length), maxWidth),
    child: OverlappingCardRow(
      itemCount: available.length,
      cardWidth: layout.rowCardWidth,
      cardHeight: layout.rowCardHeight,
      spacing: layout.rowSpacing,
      minVisible: 14 * layout.rowScale,
      height: layout.rowCardHeight + 8,
      itemBuilder: (context, index) {
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
}
