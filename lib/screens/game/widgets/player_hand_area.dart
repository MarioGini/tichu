import 'package:flutter/material.dart' hide Card;

import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/screens/game/widgets/match_end_banner.dart';
import 'package:tichu/screens/game/widgets/schupf_panel.dart';
import 'package:tichu/widgets/hand_display.dart';

/// Builds the human player's hand area: header + hand display (or schupf panel
/// / receipt panel), optionally overlaid with match-end banner.
class PlayerHandArea extends StatelessWidget {
  const PlayerHandArea({
    super.key,
    required this.hand,
    required this.selectedIndexes,
    required this.onCardTap,
    required this.isCompact,
    required this.isActive,
    required this.isFinished,
    required this.finishPosition,
    required this.showPoints,
    required this.humanScore,
    required this.humanTichu,
    required this.humanGrandTichu,
    required this.isSchupfActive,
    required this.hasSchupfReceipts,
    required this.schupfToLeft,
    required this.schupfToPartner,
    required this.schupfToRight,
    required this.schupfSentCards,
    required this.schupfReceipts,
    required this.schupfAckPending,
    required this.schupfCursorIndex,
    required this.desktopSchupfHelperEnabled,
    required this.onSetSchupfSlot,
    required this.onClearSchupfSlot,
    required this.onSubmitSchupf,
    required this.onAcknowledgeSchupf,
    required this.showMatchEndBanner,
    required this.winningTeam,
    required this.onMatchContinue,
    required this.isSelfManual,
  });

  // Hand display
  final List<Card> hand;
  final Set<int> selectedIndexes;
  final ValueChanged<int> onCardTap;
  final bool isCompact;
  final bool isActive;
  final bool isFinished;
  final int? finishPosition;
  final bool showPoints;
  final int humanScore;
  final bool humanTichu;
  final bool humanGrandTichu;
  final bool isSelfManual;

  // Schupf panel
  final bool isSchupfActive;
  final bool hasSchupfReceipts;
  final Card? schupfToLeft;
  final Card? schupfToPartner;
  final Card? schupfToRight;
  final List<Card> schupfSentCards;
  final List<SchupfReceipt> schupfReceipts;
  final bool schupfAckPending;
  final int? schupfCursorIndex;
  final bool desktopSchupfHelperEnabled;
  final void Function(SchupfSlot slot, Card card) onSetSchupfSlot;
  final void Function(SchupfSlot slot) onClearSchupfSlot;
  final VoidCallback? onSubmitSchupf;
  final VoidCallback onAcknowledgeSchupf;

  // Match end
  final bool showMatchEndBanner;
  final int? winningTeam;
  final VoidCallback? onMatchContinue;

  Widget? _buildHeader(final BuildContext context) {
    if (isCompact) return null;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.person, color: Colors.white70, size: 18),
          const SizedBox(width: 4),
          Text(
            'You',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: Colors.white),
          ),
          if (showPoints) ...[
            const SizedBox(width: 8),
            Text(
              '$humanScore pts',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: Colors.white70),
            ),
          ],
          if (humanTichu) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: humanGrandTichu ? Colors.deepOrange : Colors.orange,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: (humanGrandTichu ? Colors.deepOrange : Colors.orange)
                        .withValues(alpha: 0.4),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Text(
                humanGrandTichu ? 'GRAND' : 'TICHU',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(final BuildContext context) => LayoutBuilder(
    builder: (final context, final constraints) {
      final maxHeight = constraints.maxHeight.isFinite
          ? constraints.maxHeight
          : null;
      final showHeader = !isCompact && (maxHeight == null || maxHeight >= 120);
      final headerWidget = showHeader ? _buildHeader(context) : null;

      // Header (30) + gap (4) + container padding (12) live inside HandDisplay.
      final handDisplayOverhead = showHeader ? 46.0 : 12.0;
      final targetHeight = maxHeight == null
          ? null
          : (maxHeight - handDisplayOverhead).clamp(72.0, 240.0);

      final handDisplay = HandDisplay(
        cards: hand,
        selectedIndexes: selectedIndexes,
        onCardTap: isSelfManual ? onCardTap : (final _) {},
        isActive: isActive,
        isFinished: isFinished,
        finishPosition: finishPosition,
        targetHeight: targetHeight,
        header: headerWidget,
      );

      final baseContent = isSchupfActive
          ? SchupfPanel(
              hand: hand,
              schupfToLeft: schupfToLeft,
              schupfToPartner: schupfToPartner,
              schupfToRight: schupfToRight,
              onSetSlot: onSetSchupfSlot,
              onClearSlot: onClearSchupfSlot,
              onSubmit: onSubmitSchupf,
              header: headerWidget,
              schupfCursorIndex: schupfCursorIndex,
              desktopSchupfHelperEnabled: desktopSchupfHelperEnabled,
            )
          : hasSchupfReceipts
          ? SchupfReceiptPanel(
              hand: hand,
              schupfSentCards: schupfSentCards,
              receipts: schupfReceipts,
              onAcknowledge: onAcknowledgeSchupf,
              schupfAckPending: schupfAckPending,
              header: headerWidget,
            )
          : handDisplay;

      final handContent = showMatchEndBanner && winningTeam != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                baseContent,
                const SizedBox(height: 8),
                MatchEndBanner(
                  winningTeam: winningTeam!,
                  onContinue: onMatchContinue,
                ),
              ],
            )
          : baseContent;

      return Column(mainAxisSize: MainAxisSize.min, children: [handContent]);
    },
  );
}
