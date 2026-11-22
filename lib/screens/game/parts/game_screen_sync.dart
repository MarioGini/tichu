part of '../game_screen.dart';

mixin _GameScreenSync on _GameScreenStateBase {
  Future<void> _initializeMatch() async {
    unawaited(CardWidget.precacheCardAssets(context));
    final matchId = _sessionHandle.matchId;
    if (matchId == null) {
      throw StateError('Session handle does not have an active matchId.');
    }

    _matchSubscription = _matchService
        .watchMatch(matchId, accessToken: _sessionHandle.accessToken)
        .listen(_handleMatchView);
    if (!mounted) return;
    setState(() {
      _gameId = matchId;
    });
  }

  void _handleMatchView(final GameMatchView view) {
    _matchRevision = view.revision;
    _selfSeat = view.selfSeat;
    if (!view.roundAcknowledgementRequired) {
      _roundCompleteAcknowledged = true;
    }
    _selfControlMode = _controlModeFromSnapshot(view.snapshot);
    _gameId = view.matchId;
    _handleSnapshot(view.snapshot);
  }

  void _handleSnapshot(final PlayerSnapshot snapshot) {
    final previousTurn = _snapshot?.lastPlayedTurn;
    final wasShowingGrandTichuDecision =
        _snapshot != null && _shouldShowGrandTichuDecision(_snapshot!);
    if (!mounted) return;
    if (!snapshot.opponentAwaitingConfirmation) {
      _lastAutoConfirmKey = null;
      _autoConfirmTimer?.cancel();
      _autoConfirmTimer = null;
    }
    setState(() {
      _snapshot = snapshot;
      if (_schupfAckPending && snapshot.schupfReceipts.isEmpty) {
        _schupfAckPending = false;
        _schupfSentCards = <Card>[];
      }
      if (snapshot.schupfReceipts.isEmpty &&
          snapshot.phase != GamePhase.schupf) {
        _schupfSentCards = <Card>[];
      }
      if (_hand.length != snapshot.hand.length) {
        _selectedIndexes.clear();
        _aiSuggestionSelectionOwned = false;
      }
      _hand = List<Card>.from(snapshot.hand)..sort(compareCardsForDisplay);
      _trickCards = List<Card>.from(snapshot.deck.turn.cards);
      final uiProjection = _uiProjector.project(
        snapshot: snapshot,
        humanId: _humanId,
        isSelfManual: _isSelfManual,
        hand: _hand,
        currentSelectedIndexes: _selectedIndexes,
        currentSchupfToLeft: _schupfToLeft,
        currentSchupfToPartner: _schupfToPartner,
        currentSchupfToRight: _schupfToRight,
      );
      _pendingOpponentCards = uiProjection.pendingOpponentCards;
      _pendingOpponentPass = uiProjection.pendingOpponentPass;
      _pendingOpponentPlayerId = uiProjection.pendingOpponentPlayerId;
      if (snapshot.scoreState.roundNumber != _defaultWishRoundNumber) {
        _defaultWishFaceFromSchupf = null;
      }
      final dragonKey =
          '${snapshot.lastDragonGiveBy ?? ''}|'
          '${snapshot.lastDragonGiveTo ?? ''}';
      if (snapshot.lastDragonGiveTo == null) {
        _dragonGiveKey = null;
        _dragonGiveTurn = null;
      } else if (_dragonGiveKey != dragonKey) {
        _dragonGiveKey = dragonKey;
        _dragonGiveTurn = snapshot.lastPlayedTurn;
      }
      _schupfToLeft = uiProjection.schupfToLeft;
      _schupfToPartner = uiProjection.schupfToPartner;
      _schupfToRight = uiProjection.schupfToRight;
      _selectedIndexes
        ..clear()
        ..addAll(uiProjection.selectedIndexes);
      _aiSuggestionSelectionOwned = false;

      // Initialize / reset schupf keyboard cursor.
      final isSchupfActive =
          snapshot.phase == GamePhase.schupf &&
          !snapshot.schupfCompletedPlayers.contains(_humanId);
      if (_hasKeyboardForSchupf &&
          isSchupfActive &&
          _schupfCursorIndex == null) {
        _syncSchupfCursor(defaultToRightMost: true);
      } else if (!isSchupfActive) {
        _schupfCursorIndex = null;
      }

      final isShowingGrandTichuDecision = _shouldShowGrandTichuDecision(
        snapshot,
      );
      if (isShowingGrandTichuDecision && !wasShowingGrandTichuDecision) {
        _grandTichuSelectNo = true;
      }
    });

    _handleTurnEffects(previousTurn, snapshot.lastPlayedTurn);
    _maybeShowDragonGiveDialog(snapshot);
    _maybeShowRoundCompleteDialog(snapshot);
    _maybeAutoConfirmOpponentTurn(snapshot);
    _maybeAutoPass(snapshot);
    _maybeAutoSelectFinisher(snapshot);
    unawaited(_maybeApplyAiSuggestion(snapshot));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _schupfFocusNode.requestFocus();
    });
  }

  PlayerControlMode _controlModeFromSnapshot(final PlayerSnapshot snapshot) {
    for (final player in snapshot.players) {
      if (player.id != _humanId) continue;
      return player.type == PlayerType.automated
          ? PlayerControlMode.ai
          : PlayerControlMode.manual;
    }
    return PlayerControlMode.manual;
  }

  @override
  Future<void> _submitGameAction(final GameAction action) async {
    final matchService = _matchService;
    final gameId = _gameId;
    if (gameId == null) {
      throw StateError('Game is not ready.');
    }
    await matchService.submitAction(
      gameId,
      GameActionSubmission(
        clientActionId: _nextClientActionId(),
        action: action,
        expectedRevision: _matchRevision,
      ),
      accessToken: _sessionHandle.accessToken,
    );
  }

  @override
  Future<void> _acknowledgeRoundSummary() async {
    final snapshot = _snapshot;
    final gameId = _gameId;
    if (snapshot == null || gameId == null) return;

    await _matchService.acknowledgeRoundSummary(
      gameId,
      RoundSummaryAcknowledgement(
        clientActionId: _nextClientActionId(),
        roundNumber: snapshot.scoreState.roundNumber,
        expectedRevision: _matchRevision,
      ),
      accessToken: _sessionHandle.accessToken,
    );
  }

  @override
  Future<void> _setAutomatedActionDelay(final Duration delay) async {
    final gameId = _gameId;
    if (gameId != null && _matchService is AdjustableAutomatedActionDelay) {
      final delayService = _matchService as AdjustableAutomatedActionDelay;
      await delayService.setMatchAutomatedActionDelay(
        gameId,
        accessToken: _sessionHandle.accessToken,
        delay: delay,
      );
    }
  }

  String _nextClientActionId() =>
      '$_humanId-${++_clientActionCounter}-$_matchRevision';

  @override
  int? _resolveSelfSeat(final PlayerSnapshot? snapshot) {
    final currentSeat = _selfSeat;
    if (currentSeat != null) return currentSeat;
    if (snapshot == null) return null;
    for (final player in snapshot.players) {
      if (player.id == _humanId) {
        return player.seat;
      }
    }
    return null;
  }

  @override
  GamePlayer? _playerForRelativeSeat(
    final PlayerSnapshot? snapshot,
    final int seatOffset,
  ) {
    if (snapshot == null) return null;
    return playerAtRelativeSeat(
      snapshot.players,
      _resolveSelfSeat(snapshot),
      seatOffset,
    );
  }
}
