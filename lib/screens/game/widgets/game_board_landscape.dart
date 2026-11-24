part of 'game_board.dart';

extension _GameBoardLandscape on GameBoard {
  // ── Landscape ────────────────────────────────────────────────────────

  Widget _landscape(double w, double h) {
    final topBarH = (h * 0.13).clamp(44.0, 64.0);
    final pillW = (w * 0.19).clamp(132.0, 220.0);
    final pillH = topBarH - 6;
    final sideW = pillW + 8;
    // The hand gets about a third of the height (enough for full-height
    // cards on large screens); the schupf panel needs much more.
    final handH = expandHand
        ? h - topBarH - 4
        : (h * 0.34).clamp(110.0, CardWidget.normalHeight + 72);
    final middleH = math.max(0, h - topBarH - handH).toDouble();
    // Trick lane: middle height minus the action bar (~52) and labels.
    final laneH = math.max(0, middleH - 52 - 32).toDouble();
    final playedCardScale = (math.max(0, laneH) / (CardWidget.normalHeight + 8))
        .clamp(0.25, 1.0);
    final pendingH = math
        .min(
          CardWidget.normalHeight * playedCardScale + 8,
          math.max(0, middleH - pillH - 12),
        )
        .toDouble();
    final partnerLaneW = (CardWidget.normalWidth * playedCardScale * 1.9).clamp(
      72.0,
      130.0,
    );

    Widget sideColumn(Widget pill, Widget pending) => SizedBox(
      width: sideW,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(width: pillW, height: pillH, child: pill),
          if (reserveSidePendingSlots) ...[
            const SizedBox(height: 6),
            SizedBox(width: pillW, height: pendingH, child: pending),
          ],
        ],
      ),
    );

    final body = Column(
      children: [
        SizedBox(
          height: topBarH,
          child: Stack(
            children: [
              Positioned.fill(
                child: Row(
                  children: [
                    topBarLeading,
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: topBarCenter,
                      ),
                    ),
                    SizedBox(width: pillW + 16),
                    const Spacer(),
                    topBarTrailing,
                  ],
                ),
              ),
              Align(
                child: SizedBox(
                  width: pillW,
                  height: pillH,
                  child: topOpponent,
                ),
              ),
            ],
          ),
        ),
        if (expandHand)
          Expanded(
            child: Row(
              children: [
                sideColumn(leftOpponent, const SizedBox.shrink()),
                Expanded(
                  child: Column(
                    children: [
                      Flexible(child: handArea),
                      actionBar,
                    ],
                  ),
                ),
                sideColumn(rightOpponent, const SizedBox.shrink()),
              ],
            ),
          )
        else ...[
          SizedBox(
            height: middleH,
            child: Row(
              children: [
                sideColumn(leftOpponent, leftPendingSlot),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          // The partner's staged play gets its own lane next
                          // to the trick (mirrored by a spacer so the trick
                          // stays centred) instead of covering the trick.
                          child: Row(
                            children: [
                              if (reserveTopPendingSlot)
                                SizedBox(width: partnerLaneW),
                              Expanded(
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 520,
                                    ),
                                    child: trickArea,
                                  ),
                                ),
                              ),
                              if (reserveTopPendingSlot)
                                SizedBox(
                                  width: partnerLaneW,
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: topPendingSlot,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      actionBar,
                    ],
                  ),
                ),
                sideColumn(rightOpponent, rightPendingSlot),
              ],
            ),
          ),
          SizedBox(
            height: handH,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: handArea,
            ),
          ),
        ],
      ],
    );

    return PlayedCardSizeScope(
      cardScale: playedCardScale,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: body),
          // Partner's staged play hangs next to the partner pill.
        ],
      ),
    );
  }
}
