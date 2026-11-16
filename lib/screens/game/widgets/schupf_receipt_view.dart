part of 'schupf_panel.dart';

/// Receipt mode: the three received cards and the rest of the hand.
extension _SchupfReceiptView on SchupfPanel {
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
}
