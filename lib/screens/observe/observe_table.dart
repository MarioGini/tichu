part of 'observe_screen.dart';

/// The normal game table ([GameBoard]) seen from the followed bot: its hand
/// at the bottom, partner on top, left and right opponents at the sides.
class _ObserveTable extends StatelessWidget {
  const _ObserveTable({
    required this.controller,
    required this.snapshot,
    required this.record,
    required this.topBarLeading,
    required this.topBarTrailing,
  });

  final ObserveController controller;
  final GameSnapshot snapshot;
  final GameRecord record;
  final Widget topBarLeading;
  final Widget topBarTrailing;

  ScoreState get _score => snapshot.scoreState;

  bool get _isPlayPhase =>
      snapshot.phase == GamePhase.play &&
      !_score.roundComplete &&
      !_score.gameComplete;

  int? _finishPosition(final String id) {
    final index = _score.finishOrder.indexOf(id);
    return index == -1 ? null : index + 1;
  }

  bool _isFinished(final String id) =>
      _finishPosition(id) != null ||
      (snapshot.phase == GamePhase.play &&
          (snapshot.hands[id]?.isEmpty ?? false));

  bool _isActive(final String id) =>
      _isPlayPhase && snapshot.currentPlayerId == id;

  String? get _pendingId => snapshot.opponentAwaitingConfirmation
      ? snapshot.pendingOpponentPlayerId
      : null;

  @override
  Widget build(final BuildContext context) {
    final players = snapshot.players;
    final selfSeat = controller.followedSeat;
    final self = playerAtRelativeSeat(players, selfSeat, 0);
    final partner = playerAtRelativeSeat(players, selfSeat, TableSeat.partner);
    final left = playerAtRelativeSeat(players, selfSeat, TableSeat.left);
    final right = playerAtRelativeSeat(players, selfSeat, TableSeat.right);
    final landscape = isLandscapeTable(MediaQuery.sizeOf(context));
    final showPending = _isPlayPhase;

    return GameBoard(
      topBarLeading: topBarLeading,
      topBarCenter: ScoreBar(scoreState: _score, isTeamOne: selfSeat.isEven),
      topBarTrailing: topBarTrailing,
      reserveTopPendingSlot: showPending,
      reserveSidePendingSlots: showPending,
      topOpponent: _seat(
        partner,
        'partner',
        Icons.psychology_alt,
        pill: landscape,
      ),
      leftOpponent: _seat(left, 'left', Icons.memory, pill: landscape),
      rightOpponent: _seat(
        right,
        'right',
        Icons.smart_toy_outlined,
        pill: landscape,
      ),
      topPendingSlot: _pendingSlot(
        partner,
        label: landscape ? partner?.name : null,
      ),
      leftPendingSlot: _pendingSlot(left),
      rightPendingSlot: _pendingSlot(right),
      trickArea: _trickArea(),
      handArea: _handArea(context, self),
      actionBar: _ControlBar(
        controller: controller,
        status: _statusText(),
        highlight: _pendingId != null,
      ),
    );
  }

  /// A seat around the table; tap it to follow that bot.
  Widget _seat(
    final GamePlayer? player,
    final String position,
    final IconData icon, {
    required final bool pill,
  }) {
    if (player == null) return const SizedBox.shrink();
    final call = _score.tichuCalls[player.id] ?? TichuCall.none;
    return Tooltip(
      message: 'Follow ${player.name}',
      child: GestureDetector(
        key: Key('observe-seat-$position'),
        behavior: HitTestBehavior.opaque,
        onTap: () => controller.follow(player.seat),
        child: OpponentDisplay(
          name: player.name,
          cardCount: snapshot.hands[player.id]?.length ?? 0,
          isActive: _isActive(player.id),
          isFinished: _isFinished(player.id),
          tichuDeclared: call != TichuCall.none,
          grandTichuDeclared: call == TichuCall.grandTichu,
          finishPosition: _finishPosition(player.id),
          icon: icon,
          teamScore: _score.playerRoundPoints[player.id] ?? 0,
          showPoints: _isPlayPhase,
          pill: pill,
        ),
      ),
    );
  }

  Widget _pendingSlot(final GamePlayer? player, {final String? label}) {
    final pending = player != null && _pendingId == player.id;
    return PendingPlaySlot(
      cards: pending ? snapshot.pendingOpponentCards : const [],
      isPassed: pending && snapshot.pendingOpponentPass,
      label: label,
    );
  }

  Widget _trickArea() {
    final cards = snapshot.deck.turn.cards;
    final lastPlayedBy = snapshot.lastPlayedBy;
    final dragonTo = snapshot.lastDragonGiveTo;
    return TrickDisplay(
      cards: cards,
      currentWinnerLabel: cards.isNotEmpty && lastPlayedBy != null
          ? 'Played by ${record.nameOf(lastPlayedBy)}'
          : '',
      // The dragon was just given away: the trick is empty and nobody has
      // played since.
      dragonGiveLabel:
          dragonTo != null &&
              cards.isEmpty &&
              lastPlayedBy == snapshot.lastDragonGiveBy
          ? '${record.nameOf(dragonTo)} receives dragon'
          : '',
      activeWish: snapshot.activeWish,
      trickPoints: snapshot.trickPoints,
      showTrickPoints: _isPlayPhase,
    );
  }

  Widget _handArea(final BuildContext context, final GamePlayer? self) {
    final id = self?.id ?? '';
    final hand = [...?snapshot.hands[id]]..sort(compareCardsForDisplay);
    // The followed bot's chosen play is lifted in its hand, as in a normal
    // game when the bottom seat is played by the AI.
    final staged =
        _pendingId == id &&
            !snapshot.pendingOpponentPass &&
            snapshot.phase == GamePhase.play
        ? snapshot.pendingOpponentCards
        : const <Card>[];
    final selected = <int>{
      for (var i = 0; i < hand.length; i++)
        if (staged.any(
          (final c) => c.face == hand[i].face && c.color == hand[i].color,
        ))
          i,
    };
    final call = _score.tichuCalls[id] ?? TichuCall.none;
    final winningTeam = _score.winningTeam;
    return PlayerHandArea(
      key: const Key('observe-hand'),
      playerName: self?.name ?? '',
      hand: hand,
      selectedIndexes: selected,
      onCardTap: (_) {},
      isSelfManual: false,
      isActive: _isActive(id),
      isFinished: _isFinished(id),
      finishPosition: _finishPosition(id),
      showPoints: _isPlayPhase,
      humanScore: _score.playerRoundPoints[id] ?? 0,
      humanTichu: call != TichuCall.none,
      humanGrandTichu: call == TichuCall.grandTichu,
      isSchupfActive: false,
      hasSchupfReceipts: false,
      schupfToLeft: null,
      schupfToPartner: null,
      schupfToRight: null,
      schupfSentCards: const [],
      schupfReceipts: const [],
      schupfAckPending: false,
      schupfCursorIndex: null,
      onSetSchupfSlot: (_, _) {},
      onClearSchupfSlot: (_) {},
      onSubmitSchupf: null,
      onAcknowledgeSchupf: () {},
      showMatchEndBanner: _score.gameComplete && winningTeam != null,
      // The banner expects 0 = the bottom player's team.
      winningTeam: winningTeam == null
          ? null
          : (winningTeam == controller.followedSeat % 2 ? 0 : 1),
      onMatchContinue: () => Navigator.of(context).maybePop(),
    );
  }

  /// One line for the control bar: the staged move (with its record
  /// number) or what is going on.
  String _statusText() {
    final pendingId = _pendingId;
    if (pendingId != null) {
      return '#${record.events.length + 1}  '
          '${record.nameOf(pendingId)} ${_pendingText(snapshot)}';
    }
    if (_score.gameComplete) return 'Game over';
    if (_score.roundComplete) {
      final usTeamOne = controller.followedSeat.isEven;
      final us = usTeamOne ? _score.teamOneRound : _score.teamTwoRound;
      final them = usTeamOne ? _score.teamTwoRound : _score.teamOneRound;
      return 'Round over · Us $us : $them Them';
    }
    return switch (snapshot.phase) {
      GamePhase.grandTichu => 'Dealing · Grand Tichu…',
      GamePhase.schupf => 'Schupf · bots pass cards…',
      GamePhase.play => 'Bots are thinking…',
    };
  }
}

String _pendingText(final GameSnapshot s) {
  if (s.pendingOpponentPass) return 'passes';
  if (s.pendingOpponentCards.isEmpty) return 'calls TICHU';
  return 'plays ${cardLabels(s.pendingOpponentCards).join(' ')}';
}
