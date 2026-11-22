part of '../game_screen.dart';

/// The human's hand area and the three other seats around the table.
mixin _GameScreenSeats on _GameScreenStateBase {
  Widget _buildHandArea(final BuildContext context, final _TableFlags flags) {
    final snapshot = flags.snapshot;
    final scoreState = flags.scoreState;
    // The match-end banner expects 0 = the local player's team.
    final absoluteWinningTeam = scoreState?.winningTeam;
    final winningTeam = absoluteWinningTeam == null
        ? null
        : (absoluteWinningTeam == (_resolveSelfSeat(snapshot) ?? 0) % 2
              ? 0
              : 1);
    return PlayerHandArea(
      hand: _hand,
      selectedIndexes: _selectedIndexes,
      onCardTap: _toggleSelect,
      isActive: flags.showPlayInfo && snapshot?.currentPlayerId == _humanId,
      isFinished: flags.isFinished(_humanId),
      finishPosition: flags.finishPositionFor(_humanId),
      showPoints: flags.showPlayInfo,
      humanScore: flags.roundPointsFor(_humanId),
      humanTichu: flags.humanTichu,
      humanGrandTichu: flags.humanGrandTichu,
      isSelfManual: _isSelfManual,
      isSchupfActive: flags.isSchupfActive,
      hasSchupfReceipts: flags.hasSchupfReceipts,
      schupfToLeft: _schupfToLeft,
      schupfToPartner: _schupfToPartner,
      schupfToRight: _schupfToRight,
      schupfSentCards: _schupfSentCards,
      schupfReceipts: snapshot?.schupfReceipts ?? const [],
      schupfAckPending: _schupfAckPending,
      schupfCursorIndex: _schupfCursorIndex,
      onSetSchupfSlot: _setSchupfSlot,
      onClearSchupfSlot: _clearSchupfSlot,
      onSubmitSchupf: _submitSchupf,
      onAcknowledgeSchupf: _acknowledgeSchupfReceipts,
      showMatchEndBanner:
          (scoreState?.gameComplete ?? false) && winningTeam != null,
      winningTeam: winningTeam,
      onMatchContinue: () => Navigator.of(context).pop(),
    );
  }

  OpponentDisplay _buildOpponent(
    final _TableFlags flags, {
    required final GamePlayer? player,
    required final String fallbackName,
    required final IconData icon,
    final bool pill = false,
  }) {
    final playerId = player?.id;
    final call = flags.tichuCalls[playerId];
    return OpponentDisplay(
      name: player?.name ?? fallbackName,
      cardCount: flags.snapshot?.opponentCardCounts[playerId] ?? 0,
      isActive:
          flags.showPlayInfo &&
          playerId != null &&
          flags.snapshot?.currentPlayerId == playerId,
      isFinished: playerId != null && flags.isFinished(playerId),
      tichuDeclared: call == TichuCall.tichu || call == TichuCall.grandTichu,
      grandTichuDeclared: call == TichuCall.grandTichu,
      finishPosition: flags.finishPositionFor(playerId),
      icon: icon,
      teamScore: flags.roundPointsFor(playerId),
      showPoints: flags.showPlayInfo,
      pill: pill,
    );
  }

  Widget _buildPendingSlot({
    required final String? playerId,
    required final bool showPending,
    required final Alignment alignment,
    final String? label,
  }) {
    final isActive = showPending && _pendingOpponentPlayerId == playerId;
    return PendingPlaySlot(
      cards: isActive ? _pendingOpponentCards : const [],
      isPassed: isActive && _pendingOpponentPass,
      label: label,
    );
  }
}
