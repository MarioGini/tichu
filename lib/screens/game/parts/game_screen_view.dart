part of '../game_screen.dart';

/// Values derived from the current snapshot that decide what the table shows.
class _TableFlags {
  _TableFlags({
    required this.snapshot,
    required this.isSchupfActive,
    required this.hasSchupfReceipts,
    required this.pendingReceipts,
    required this.isPlayPhase,
    required this.humanCall,
  });

  final PlayerSnapshot? snapshot;
  final bool isSchupfActive;
  final bool hasSchupfReceipts;
  final bool pendingReceipts;

  /// Play phase of a running round (no turn actions once the round is over).
  final bool isPlayPhase;
  final TichuCall? humanCall;

  /// Points, turn indicators and turn actions are shown together.
  bool get showPlayInfo => isPlayPhase && !pendingReceipts;
  bool get humanTichu =>
      humanCall == TichuCall.tichu || humanCall == TichuCall.grandTichu;
  bool get humanGrandTichu => humanCall == TichuCall.grandTichu;
  ScoreState? get scoreState => snapshot?.scoreState;
  Map<String, TichuCall> get tichuCalls =>
      scoreState?.tichuCalls ?? const <String, TichuCall>{};

  int roundPointsFor(final String? playerId) =>
      playerId == null ? 0 : scoreState?.playerRoundPoints[playerId] ?? 0;

  int? finishPositionFor(final String? playerId) {
    if (playerId == null) return null;
    final index = (scoreState?.finishOrder ?? const <String>[]).indexOf(
      playerId,
    );
    return index == -1 ? null : index + 1;
  }

  bool isFinished(final String? playerId) {
    final cardsLeft = snapshot?.opponentCardCounts[playerId];
    return cardsLeft == 0 || finishPositionFor(playerId) != null;
  }
}

mixin _GameScreenView on _GameScreenStateBase, _GameScreenSeats {
  _TableFlags _tableFlags() {
    final snapshot = _snapshot;
    final scoreState = snapshot?.scoreState;
    final receipts = snapshot?.schupfReceipts ?? const <SchupfReceipt>[];
    return _TableFlags(
      snapshot: snapshot,
      isSchupfActive:
          snapshot != null &&
          snapshot.phase == GamePhase.schupf &&
          (!snapshot.schupfCompletedPlayers.contains(_humanId) ||
              (!_isSelfManual &&
                  snapshot.pendingOpponentPlayerId == _humanId &&
                  snapshot.pendingOpponentCards.length == 3)),
      hasSchupfReceipts: !_schupfAckPending && receipts.isNotEmpty,
      pendingReceipts: _schupfAckPending || receipts.isNotEmpty,
      isPlayPhase:
          snapshot?.phase == GamePhase.play &&
          !(scoreState?.roundComplete ?? false) &&
          !(scoreState?.gameComplete ?? false),
      humanCall: scoreState?.tichuCalls[_humanId],
    );
  }

  Widget _buildTable(final BuildContext context) {
    final flags = _tableFlags();
    final snapshot = flags.snapshot;
    final scoreState = flags.scoreState;
    final partnerPlayer = _playerForRelativeSeat(snapshot, 2);
    final leftPlayer = _playerForRelativeSeat(snapshot, -1);
    final rightPlayer = _playerForRelativeSeat(snapshot, 1);
    final landscape = isLandscapeTable(MediaQuery.sizeOf(context));
    final showPending = flags.isPlayPhase;

    return Scaffold(
      body: Focus(
        focusNode: _schupfFocusNode,
        autofocus: true,
        onKeyEvent: (final node, final event) => handleDirectionalEnterKeyEvent(
          event,
          onEnter: _handleShortcutEnter,
          onLeft: _handleShortcutLeft,
          onRight: _handleShortcutRight,
        ),
        child: SafeArea(
          child: GameBoard(
            expandHand:
                snapshot?.phase == GamePhase.schupf || flags.pendingReceipts,
            topBarLeading: _TopBarButton(
              tooltip: 'Leave table',
              icon: Icons.arrow_back_rounded,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            topBarCenter: scoreState == null
                ? const SizedBox.shrink()
                : ScoreBar(
                    scoreState: scoreState,
                    isTeamOne: (_resolveSelfSeat(snapshot) ?? 0).isEven,
                  ),
            topBarTrailing: _TopBarButton(
              tooltip: 'Options',
              icon: Icons.settings,
              onPressed: _showOptionsDialog,
            ),
            reserveTopPendingSlot: showPending,
            reserveSidePendingSlots: showPending,
            topOpponent: _buildOpponent(
              flags,
              player: partnerPlayer,
              fallbackName: 'Partner',
              icon: Icons.psychology_alt,
              pill: landscape,
            ),
            topPendingSlot: _buildPendingSlot(
              playerId: partnerPlayer?.id,
              showPending: showPending,
              alignment: landscape
                  ? Alignment.topCenter
                  : Alignment.bottomCenter,
              label: landscape ? partnerPlayer?.name : null,
            ),
            leftOpponent: _buildOpponent(
              flags,
              player: leftPlayer,
              fallbackName: 'Left Opponent',
              icon: Icons.memory,
              pill: landscape,
            ),
            leftPendingSlot: _buildPendingSlot(
              playerId: leftPlayer?.id,
              showPending: showPending,
              alignment: Alignment.bottomRight,
            ),
            rightPendingSlot: _buildPendingSlot(
              playerId: rightPlayer?.id,
              showPending: showPending,
              alignment: Alignment.bottomLeft,
            ),
            rightOpponent: _buildOpponent(
              flags,
              player: rightPlayer,
              fallbackName: 'Right Opponent',
              icon: Icons.smart_toy_outlined,
              pill: landscape,
            ),
            trickArea: _buildTrickArea(flags),
            handArea: _buildHandArea(context, flags),
            actionBar: _buildActionBar(flags),
          ),
        ),
      ),
    );
  }

  Widget _buildTrickArea(final _TableFlags flags) {
    final snapshot = flags.snapshot;
    String nameOf(final String id) =>
        snapshot?.players
            .where((final player) => player.id == id)
            .firstOrNull
            ?.name ??
        'Unknown';

    var trickLabel = '';
    final lastPlayedBy = snapshot?.lastPlayedBy;
    if (_trickCards.isNotEmpty && lastPlayedBy != null) {
      trickLabel = 'Played by ${nameOf(lastPlayedBy)}';
    }
    var dragonLabel = '';
    final dragonTarget = snapshot?.lastDragonGiveTo;
    if (_dragonGiveTurn != null &&
        snapshot?.lastPlayedTurn == _dragonGiveTurn &&
        dragonTarget != null) {
      dragonLabel = '${nameOf(dragonTarget)} receives dragon';
    }

    return TrickDisplay(
      cards: _trickCards,
      currentWinnerLabel: trickLabel,
      dragonGiveLabel: dragonLabel,
      activeWish: snapshot?.activeWish ?? CardFace.none,
      trickPoints: snapshot?.trickPoints ?? 0,
      showTrickPoints: flags.showPlayInfo,
    ).withBombOverlay(
      showOverlay: _showBombOverlay,
      slide: _bombSlide,
      scale: _bombScale,
    );
  }

  Widget _buildActionBar(final _TableFlags flags) {
    final snapshot = flags.snapshot;
    final manual = _isSelfManual;
    final showTurnActions = flags.showPlayInfo;
    final canPlayAny = snapshot != null && _canPlayAny(snapshot);
    final canPass = snapshot != null && _canPass(snapshot);
    final showGrandTichuDecision =
        snapshot != null && _shouldShowGrandTichuDecision(snapshot);
    final roundComplete = flags.scoreState?.roundComplete ?? false;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showGrandTichuDecision)
          GrandTichuBanner(
            selectNo: _grandTichuSelectNo,
            isPending: _grandTichuDialogOpen,
            onDecision: (final call) =>
                unawaited(_submitGrandTichuDecision(call)),
            onToggle: (final selectNo) {
              setState(() {
                _grandTichuSelectNo = selectNo;
              });
            },
          ),
        ActionBar(
          showTurnActions: showTurnActions,
          showBomb:
              manual && showTurnActions && (snapshot?.hasBombInHand ?? false),
          isPlayEnabled:
              manual &&
              snapshot != null &&
              _canPlaySelected(snapshot) &&
              !flags.pendingReceipts,
          isBombEnabled:
              manual &&
              snapshot != null &&
              snapshot.canBomb &&
              !flags.pendingReceipts,
          isPassEnabled: manual && showTurnActions && canPass,
          isPassPreferred:
              manual &&
              showTurnActions &&
              snapshot?.currentPlayerId == _humanId &&
              !(snapshot?.opponentAwaitingConfirmation ?? false) &&
              canPass &&
              !canPlayAny,
          isSchupfEnabled:
              flags.isSchupfActive &&
              _schupfToLeft != null &&
              _schupfToPartner != null &&
              _schupfToRight != null,
          showSchupf: false,
          showDeclareTichu:
              manual &&
              !roundComplete &&
              !showGrandTichuDecision &&
              ((snapshot != null && snapshot.phase != GamePhase.play) ||
                  (snapshot?.canCallTichu ?? false)) &&
              !flags.humanTichu,
          onPlay: _playSelected,
          onBomb: _playBomb,
          onPass: _pass,
          onSchupf: _submitSchupf,
          onDeclareTichu: _declareTichu,
        ),
      ],
    );
  }
}
