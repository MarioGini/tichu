part of '../game_screen.dart';

mixin _GameScreenDialogs on _GameScreenBindings {
  Future<void> _showOptionsDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (final context) => OptionsDialog(
        aiSuggestionEnabled: _aiSuggestionEnabled,
        opponentDelay: _opponentDelaySeconds,
        autoPassEnabled: _autoPassEnabled,
        soundEnabled: _soundEnabled,
        onAiSuggestionChanged: (final value) {
          setState(() {
            _aiSuggestionEnabled = value;
          });
          if (!value) {
            _clearAiSuggestionSelection();
            return;
          }
          final snapshot = _snapshot;
          if (snapshot == null) return;
          unawaited(_maybeApplyAiSuggestion(snapshot));
        },
        onOpponentDelayChanged: (final value) {
          setState(() {
            _opponentDelaySeconds = value;
          });
          final delayMs = (value * 1000).round();
          unawaited(_setAutomatedActionDelay(Duration(milliseconds: delayMs)));
        },
        onAutoPassChanged: (final value) {
          setState(() {
            _autoPassEnabled = value;
          });
        },
        onSoundChanged: (final value) {
          setState(() {
            _soundEnabled = value;
          });
          SoundEffects.setEnabled(value);
        },
      ),
    );
  }

  void _maybeShowRoundCompleteDialog(final PlayerSnapshot snapshot) {
    final scoreState = snapshot.scoreState;
    if (!scoreState.roundComplete) return;
    if (scoreState.roundNumber <= _lastDialogRoundNumber) return;

    _lastDialogRoundNumber = scoreState.roundNumber;
    _roundCompleteAcknowledged = false;
    final tichuSuccess = _buildTichuSuccessMessage(snapshot);
    final matchSuccess = _buildMatchSuccessMessage(scoreState);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      if (matchSuccess != null) {
        await _showCelebrationBeforeSummary(
          message: matchSuccess.message,
          label: 'MATCH',
          isPositive: matchSuccess.isPositive,
        );
        if (!mounted) return;
      }

      if (tichuSuccess != null) {
        await _showCelebrationBeforeSummary(
          message: tichuSuccess.message,
          label: 'TICHU',
          isPositive: tichuSuccess.isPositive,
        );
        if (!mounted) return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (final context) => RoundSummaryScreen(
            scoreState: scoreState,
            onBackHome: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            onStartNextRound: scoreState.gameComplete
                ? null
                : () async {
                    setState(() {
                      _roundCompleteAcknowledged = true;
                    });
                    await _startRound();
                  },
          ),
        ),
      );
    });
  }

  Future<void> _showCelebrationBeforeSummary({
    required final String message,
    required final String label,
    required final bool isPositive,
  }) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder:
            (final context, final animation, final secondaryAnimation) =>
                TichuCelebrationOverlay(
                  message: message,
                  label: label,
                  isPositive: isPositive,
                ),
      ),
    );
  }

  ({String message, bool isPositive})? _buildMatchSuccessMessage(
    final ScoreState scoreState,
  ) {
    if (!scoreState.gameComplete) return null;
    return switch (scoreState.winningTeam) {
      0 => (message: 'Your team wins the match!', isPositive: true),
      1 => (message: 'Other team wins the match!', isPositive: false),
      _ => (message: 'The match ends in a tie!', isPositive: false),
    };
  }

  ({String message, bool isPositive})? _buildTichuSuccessMessage(
    final PlayerSnapshot snapshot,
  ) {
    final finishOrder = snapshot.scoreState.finishOrder;
    if (finishOrder.isEmpty) return null;

    final winningPlayerId = finishOrder.first;
    final winningTichuCall = snapshot.scoreState.tichuCalls[winningPlayerId];
    if (winningTichuCall == null || winningTichuCall == TichuCall.none) {
      return null;
    }

    var winningPlayerName = 'Unknown';
    for (final player in snapshot.players) {
      if (player.id == winningPlayerId) {
        winningPlayerName = player.name;
        break;
      }
    }

    final callLabel = winningTichuCall == TichuCall.grandTichu
        ? 'Grand Tichu'
        : 'Tichu';
    final isPositive = _isOurTeamPlayer(snapshot, winningPlayerId);
    if (isPositive) {
      return (
        message: '$winningPlayerName successfully called $callLabel!',
        isPositive: true,
      );
    }
    return (
      message: '$winningPlayerName made $callLabel against your team.',
      isPositive: false,
    );
  }

  bool _isOurTeamPlayer(final PlayerSnapshot snapshot, final String playerId) {
    final mySeat = snapshot.players
        .firstWhere((final player) => player.id == _humanId)
        .seat;
    final winnerSeat = snapshot.players
        .firstWhere((final player) => player.id == playerId)
        .seat;
    return mySeat % 2 == winnerSeat % 2;
  }

  void _maybeShowDragonGiveDialog(final PlayerSnapshot snapshot) {
    if (!_isSelfManual) return;
    if (_dragonGiveDialogOpen) return;
    if (snapshot.pendingDragonGiveBy != _humanId) return;
    if (snapshot.pendingDragonGiveTargets.isEmpty) return;
    if (_gameId == null) return;

    _dragonGiveDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final targetIds = _orderDragonGiveTargetsForDisplay(snapshot);
      final selectedTarget = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (final context) => AlertDialog(
          title: const Text('Who receives the dragon?'),
          actionsAlignment: MainAxisAlignment.center,
          actions: targetIds.map((final targetId) {
            final name = snapshot.players
                .firstWhere((final player) => player.id == targetId)
                .name;
            return TextButton(
              onPressed: () => Navigator.of(context).pop(targetId),
              child: Text(name),
            );
          }).toList(),
        ),
      );

      _dragonGiveDialogOpen = false;
      if (!mounted) return;
      if (selectedTarget == null) return;
      try {
        await _submitGameAction(
          GiveDragonAction(playerId: _humanId, targetPlayerId: selectedTarget),
        );
      } on Object catch (error) {
        _showSnack(error.toString());
      }
    });
  }

  List<String> _orderDragonGiveTargetsForDisplay(
    final PlayerSnapshot snapshot,
  ) {
    final targetIds = List<String>.from(snapshot.pendingDragonGiveTargets);
    final seatById = {
      for (final player in snapshot.players) player.id: player.seat,
    };
    final humanSeat = seatById[_humanId];
    final playerCount = snapshot.players.length;
    if (humanSeat == null || playerCount <= 0) {
      return targetIds;
    }

    int displayPriority(final String playerId) {
      final seat = seatById[playerId];
      if (seat == null) return 3;
      final relativeSeat = (seat - humanSeat + playerCount) % playerCount;
      if (relativeSeat == playerCount - 1) return 0;
      if (relativeSeat == 1) return 1;
      return 2;
    }

    targetIds.sort((final a, final b) {
      final priorityComparison = displayPriority(
        a,
      ).compareTo(displayPriority(b));
      if (priorityComparison != 0) {
        return priorityComparison;
      }
      final seatA = seatById[a] ?? playerCount;
      final seatB = seatById[b] ?? playerCount;
      return seatA.compareTo(seatB);
    });

    return targetIds;
  }

  bool _shouldShowGrandTichuDecision(final PlayerSnapshot snapshot) {
    if (!_isSelfManual) return false;
    if (snapshot.phase != GamePhase.grandTichu) return false;
    if (snapshot.currentPlayerId != _humanId) return false;
    if (snapshot.grandTichuDecisions.containsKey(_humanId)) return false;
    final humanCall = snapshot.scoreState.tichuCalls[_humanId];
    if (humanCall != null && humanCall != TichuCall.none) return false;
    return true;
  }

  @override
  Future<CardFace?> _promptWish({final CardFace? defaultWish}) async {
    if (_wishDialogOpen) return null;
    if (!mounted) return null;

    _wishDialogOpen = true;
    final selection = await showDialog<CardFace>(
      context: context,
      barrierDismissible: false,
      builder: (final context) => WishDialog(defaultWish: defaultWish),
    );
    _wishDialogOpen = false;
    return selection;
  }

  Future<void> _submitGrandTichuDecision(final bool call) async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    if (_grandTichuDialogOpen) return;
    _grandTichuDialogOpen = true;
    try {
      await _submitGameAction(
        GrandTichuDecisionAction(playerId: _humanId, call: call),
      );
    } on Object catch (error) {
      _showSnack(error.toString());
    } finally {
      _grandTichuDialogOpen = false;
    }
  }

  Future<void> _submitSchupf() async {
    if (!_isSelfManual) return;
    final snapshot = _snapshot;
    if (snapshot == null) return;
    if (snapshot.phase != GamePhase.schupf) return;
    if (snapshot.schupfCompletedPlayers.contains(_humanId)) return;
    if (_schupfToLeft == null ||
        _schupfToPartner == null ||
        _schupfToRight == null) {
      _showSnack('Pick one card for each player before sending.');
      return;
    }

    final toLeft = _schupfToLeft!;
    final toPartner = _schupfToPartner!;
    final toRight = _schupfToRight!;

    final wishDefault = defaultWishFaceFromSchupf(
      toLeft: toLeft,
      toPartner: toPartner,
      toRight: toRight,
    );

    try {
      await _submitGameAction(
        SchupfAction(
          playerId: _humanId,
          toLeft: toLeft,
          toPartner: toPartner,
          toRight: toRight,
        ),
      );
      setState(() {
        _schupfSentCards = <Card>[toLeft, toPartner, toRight];
        _defaultWishFaceFromSchupf = wishDefault;
        _defaultWishRoundNumber = snapshot.scoreState.roundNumber;
        _selectedIndexes.clear();
        _schupfToLeft = null;
        _schupfToPartner = null;
        _schupfToRight = null;
      });
    } on Object catch (error) {
      _showSnack(error.toString());
    }
  }
}
