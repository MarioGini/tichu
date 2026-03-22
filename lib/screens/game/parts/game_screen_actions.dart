part of '../game_screen.dart';

mixin _GameScreenActions on _GameScreenBindings {
  void _toggleSelect(final int index) {
    if (!_isSelfManual) return;
    setState(() {
      _aiSuggestionSelectionOwned = false;
      if (_selectedIndexes.contains(index)) {
        _selectedIndexes.remove(index);
      } else {
        _selectedIndexes.add(index);
      }
    });
    _requestKeyboardFocus();
  }

  @override
  Future<void> _startRound() async {
    if (_gameId == null || !_roundCompleteAcknowledged) return;
    await _backend.startNewRound(_gameId!);
  }

  Future<void> _playSelected() async {
    if (!_isSelfManual) return;
    final snapshot = _snapshot;
    if (snapshot == null || _selectedIndexes.isEmpty) return;

    final selectedTurn = _resolveSelectedTurn(snapshot);
    if (selectedTurn == null) {
      _showSnack('Selected cards do not form a valid play.');
      return;
    }

    var inputWish = CardFace.none;
    if (_playController.requiresWishInput(selectedTurn)) {
      CardFace? defaultWish;
      final schupfWish = _defaultWishFaceFromSchupf;
      if (schupfWish != null && isWishableFace(schupfWish)) {
        defaultWish = schupfWish;
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
        _aiSuggestionSelectionOwned = false;
      });
    } on Object catch (error) {
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

    final playableBomb = _playController.firstPlayableBomb(
      snapshot.deck,
      _hand,
    );

    if (playableBomb == null) {
      _showSnack('No bomb can beat the current play.');
      return;
    }

    setState(() {
      _selectedIndexes
        ..clear()
        ..addAll(_playController.cardIndicesInHand(_hand, playableBomb.cards));
      _aiSuggestionSelectionOwned = false;
    });

    try {
      await _backend.submitAction(
        snapshot.gameId,
        PlayTurnAction(playerId: _humanId, cards: playableBomb.cards),
      );
      setState(() {
        _selectedIndexes.clear();
        _aiSuggestionSelectionOwned = false;
      });
    } on Object catch (error) {
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
    } on Object catch (error) {
      _showSnack(error.toString());
    }
  }

  @override
  Future<void> _pass() async {
    if (!_isSelfManual) return;
    final snapshot = _snapshot;
    if (snapshot == null) return;
    if (!_canPass(snapshot)) return;
    try {
      await _backend.submitAction(
        snapshot.gameId,
        const PassAction(playerId: 'player-0'),
      );
      setState(() {
        _selectedIndexes.clear();
        _aiSuggestionSelectionOwned = false;
      });
    } on Object catch (error) {
      _showSnack(error.toString());
    }
  }

  Future<void> _declareTichu() async {
    if (!_isSelfManual) return;
    final snapshot = _snapshot;
    if (snapshot == null) {
      return;
    }
    final canDeclarePrePlay = snapshot.phase != GamePhase.play;
    if (!snapshot.canCallTichu && !canDeclarePrePlay) return;
    try {
      await _backend.submitAction(
        snapshot.gameId,
        const CallTichuAction(playerId: 'player-0'),
      );
    } on Object catch (error) {
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
    try {
      await _backend.submitAction(
        snapshot.gameId,
        const AcknowledgeSchupfAction(playerId: 'player-0'),
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _schupfAckPending = false;
        });
      }
      _showSnack(error.toString());
    }
  }
}
