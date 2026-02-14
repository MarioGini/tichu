part of '../game_screen.dart';

mixin _GameScreenActions on _GameScreenBindings {
  void _toggleSelect(int index) {
    if (!_isSelfManual) return;
    setState(() {
      if (_selectedIndexes.contains(index)) {
        _selectedIndexes.remove(index);
      } else {
        _selectedIndexes.add(index);
      }
    });
  }

  @override
  Future<void> _startRound() async {
    if (_gameId == null || !_roundCompleteAcknowledged) return;
    await _backend.startNewRound(_gameId!);
  }

  Future<void> _playSelected() async {
    if (!_isSelfManual) return;
    final snapshot = _snapshot;
    if (snapshot == null || _selectedIndexes.isEmpty) {
      return;
    }

    if (snapshot.schupfReceipts.isNotEmpty || _schupfAckPending) {
      return;
    }

    if (snapshot.phase != GamePhase.play) {
      return;
    }

    if (snapshot.pendingDragonGiveBy == _humanId) {
      return;
    }

    if (snapshot.currentPlayerId != _humanId) {
      return;
    }

    final selectedTurn = _resolveSelectedTurn(snapshot);
    if (selectedTurn == null) {
      _showSnack('Selected cards do not form a valid play.');
      return;
    }

    CardFace inputWish = CardFace.none;
    if (selectedTurn.cards.any((card) => card.face == CardFace.mahJong)) {
      CardFace? defaultWish;
      if (_defaultWishRoundNumber == snapshot.scoreState.roundNumber) {
        final schupfWish = _defaultWishFaceFromSchupf;
        if (schupfWish != null && _isWishableFace(schupfWish)) {
          defaultWish = schupfWish;
        }
      }
      final wish = await _promptWish(defaultWish: defaultWish);
      if (!mounted) return;
      if (wish == null) return;
      inputWish = wish;
    }

    try {
      await _backend.submitAction(
        snapshot.gameId,
        PlayTurnAction(
          playerId: _humanId,
          cards: selectedTurn.cards,
          inputWish: inputWish,
        ),
      );
      setState(() {
        _selectedIndexes.clear();
      });
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  Future<void> _playBomb() async {
    if (!_isSelfManual) return;
    final snapshot = _snapshot;
    if (snapshot == null) return;

    if (snapshot.schupfReceipts.isNotEmpty || _schupfAckPending) return;
    if (snapshot.phase != GamePhase.play) return;
    if (snapshot.pendingDragonGiveBy == _humanId) return;

    // Find all bombs in the hand and pick the first one that can be played.
    final bombs = _turnRules.bombsInHand(_hand);
    if (bombs.isEmpty) return;

    final playableBomb = _turnRules.firstPlayableBomb(snapshot.deck, _hand);

    if (playableBomb == null) {
      _showSnack('No bomb can beat the current play.');
      return;
    }

    // Auto-select the bomb cards in the hand display.
    final indices = <int>{};
    final used = <int>{};
    for (final card in playableBomb.cards) {
      for (var i = 0; i < _hand.length; i++) {
        if (!used.contains(i) && _hand[i] == card) {
          indices.add(i);
          used.add(i);
          break;
        }
      }
    }
    setState(() {
      _selectedIndexes
        ..clear()
        ..addAll(indices);
    });

    try {
      await _backend.submitAction(
        snapshot.gameId,
        PlayTurnAction(
          playerId: _humanId,
          cards: playableBomb.cards,
          inputWish: CardFace.none,
        ),
      );
      setState(() {
        _selectedIndexes.clear();
      });
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  @override
  Future<void> _confirmOpponentTurn() async {
    final snapshot = _snapshot;
    if (snapshot == null || !snapshot.opponentAwaitingConfirmation) {
      return;
    }

    try {
      await _backend.submitAction(
        snapshot.gameId,
        ConfirmOpponentTurnAction(playerId: _humanId),
      );
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  @override
  Future<void> _pass() async {
    if (!_isSelfManual) return;
    final snapshot = _snapshot;
    if (snapshot == null || snapshot.currentPlayerId != _humanId) {
      return;
    }
    if (snapshot.schupfReceipts.isNotEmpty || _schupfAckPending) {
      return;
    }
    if (snapshot.phase != GamePhase.play) return;
    if (snapshot.pendingDragonGiveBy == _humanId) {
      return;
    }
    try {
      await _backend.submitAction(
        snapshot.gameId,
        const PassAction(playerId: 'player-0'),
      );
      setState(() {
        _selectedIndexes.clear();
      });
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  Future<void> _declareTichu() async {
    if (!_isSelfManual) return;
    final snapshot = _snapshot;
    if (snapshot == null || snapshot.currentPlayerId != _humanId) {
      return;
    }
    if (snapshot.schupfReceipts.isNotEmpty || _schupfAckPending) {
      return;
    }
    if (snapshot.phase != GamePhase.play) return;
    if (snapshot.pendingDragonGiveBy == _humanId) {
      return;
    }
    try {
      await _backend.submitAction(
        snapshot.gameId,
        const CallTichuAction(playerId: 'player-0'),
      );
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  Future<void> _acknowledgeSchupfReceipts() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    if (_schupfAckPending) return;
    setState(() {
      _schupfAckPending = true;
    });
    final delayMs = (_opponentDelaySeconds * 1000).round();
    await Future.delayed(Duration(milliseconds: delayMs));
    try {
      await _backend.submitAction(
        snapshot.gameId,
        const AcknowledgeSchupfAction(playerId: 'player-0'),
      );
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _schupfAckPending = false;
        });
      }
    }
  }
}

bool _isWishableFace(CardFace face) {
  switch (face) {
    case CardFace.two:
    case CardFace.three:
    case CardFace.four:
    case CardFace.five:
    case CardFace.six:
    case CardFace.seven:
    case CardFace.eight:
    case CardFace.nine:
    case CardFace.ten:
    case CardFace.jack:
    case CardFace.queen:
    case CardFace.king:
    case CardFace.ace:
      return true;
    default:
      return false;
  }
}
