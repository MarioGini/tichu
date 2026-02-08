part of '../game_screen.dart';

mixin _GameScreenActions on _GameScreenBindings {
  void _toggleSelect(int index) {
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
    setState(() {
      _canDeclareTichu = true;
      _tichuDeclared = false;
    });
    await _backend.startNewRound(_gameId!);
  }

  Future<void> _playSelected() async {
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
      final wish = await _promptWish();
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
        _canDeclareTichu = false;
      });
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  Future<void> _playBomb() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;

    if (snapshot.schupfReceipts.isNotEmpty || _schupfAckPending) return;
    if (snapshot.phase != GamePhase.play) return;
    if (snapshot.pendingDragonGiveBy == _humanId) return;

    // Find all bombs in the hand and pick the first one that can be played.
    final bombs = getBombs(_hand);
    if (bombs.isEmpty) return;

    TichuTurn? playableBomb;
    for (final bomb in bombs) {
      final updated = _turnHandler.handleTurn(
        snapshot.deck,
        List<Card>.from(bomb.cards),
        CardFace.none,
        hand: _hand,
      );
      if (updated.turn != TichuTurn.InvalidTurn()) {
        playableBomb = bomb;
        break;
      }
    }

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
        _canDeclareTichu = false;
      });
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  @override
  Future<void> _confirmAiTurn() async {
    final snapshot = _snapshot;
    if (snapshot == null || !snapshot.aiAwaitingConfirmation) {
      return;
    }

    try {
      await _backend.submitAction(
        snapshot.gameId,
        ConfirmAiTurnAction(playerId: _humanId),
      );
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  @override
  Future<void> _pass() async {
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
        _canDeclareTichu = false;
      });
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  Future<void> _declareTichu() async {
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
    setState(() {
      _tichuDeclared = true;
      _canDeclareTichu = false;
    });
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
    final delayMs = (_aiDelaySeconds * 1000).round();
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
