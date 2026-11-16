part of '../game_screen.dart';

mixin _GameScreenHelpers on _GameScreenStateBase {
  @override
  void _handleTurnEffects(final TichuTurn? previous, final TichuTurn? current) {
    if (current == null || previous == current) return;
    if (current.type == TurnType.dog) {
      unawaited(SoundEffects.playDog());
    } else if (current.type == TurnType.bomb) {
      unawaited(SoundEffects.playBomb());
      _triggerBombAnimation();
    }
  }

  @override
  void _maybeAutoConfirmOpponentTurn(final PlayerSnapshot snapshot) {
    if (!snapshot.opponentAwaitingConfirmation) return;
    if (snapshot.scoreState.roundComplete) return;
    final pendingPlayer = snapshot.pendingOpponentPlayerId;
    if (pendingPlayer == null) return;
    if (_isSelfManual && pendingPlayer == _humanId) return;

    final pendingKey = [
      snapshot.gameId,
      pendingPlayer,
      snapshot.pendingOpponentPass.toString(),
      snapshot.pendingOpponentCards
          .map((final card) => card.hashCode)
          .join(','),
    ].join('|');

    if (_lastAutoConfirmKey == pendingKey) return;
    _lastAutoConfirmKey = pendingKey;

    final delayMs = (_opponentDelaySeconds * 1000).round();
    _autoConfirmTimer?.cancel();
    _autoConfirmTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      if (_snapshot?.opponentAwaitingConfirmation != true) return;
      unawaited(_confirmOpponentTurn());
    });
  }

  @override
  void _maybeAutoPass(final PlayerSnapshot snapshot) {
    if (!_isSelfManual) return;
    if (!_autoPassEnabled) return;
    if (snapshot.phase != GamePhase.play) return;
    // A double victory ends the round while others still hold cards.
    if (snapshot.scoreState.roundComplete) return;
    if (snapshot.currentPlayerId != _humanId) return;
    if (snapshot.pendingDragonGiveBy == _humanId) return;
    if (_canPlayAny(snapshot)) return;

    final key = [
      snapshot.gameId,
      snapshot.currentPlayerId,
      snapshot.deck.turn.type.name,
      snapshot.deck.turn.value.toString(),
      _hand.length.toString(),
    ].join('|');
    if (_lastAutoPassKey == key) return;
    _lastAutoPassKey = key;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = _snapshot;
      if (current == null) return;
      if (current.phase != GamePhase.play) return;
      if (current.scoreState.roundComplete) return;
      if (current.currentPlayerId != _humanId) return;
      if (_canPlayAny(current)) return;
      unawaited(_pass());
    });
  }

  @override
  void _maybeAutoSelectFinisher(final PlayerSnapshot snapshot) {
    if (!_isSelfManual) return;
    if (snapshot.scoreState.roundComplete) return;
    final shouldAutoSelect = _playController.shouldAutoSelectFinisher(
      snapshot: snapshot,
      humanId: _humanId,
      hand: _hand,
      schupfAckPending: _schupfAckPending,
      hasSelectedCards: _selectedIndexes.isNotEmpty,
    );
    if (!shouldAutoSelect) {
      return;
    }

    setState(() {
      _selectedIndexes
        ..clear()
        ..addAll(List<int>.generate(_hand.length, (final index) => index));
    });
  }

  void _triggerBombAnimation() {
    setState(() {
      _showBombOverlay = true;
    });
    _bombController.forward(from: 0);
  }

  List<Card> _selectedCards() {
    final selected = <Card>[];
    for (var i = 0; i < _hand.length; i++) {
      if (_selectedIndexes.contains(i)) {
        selected.add(_hand[i]);
      }
    }
    return selected;
  }

  @override
  TichuTurn? _resolveSelectedTurn(final PlayerSnapshot snapshot) =>
      _playController.resolveSelectedTurn(
        snapshot: snapshot,
        selectedCards: _selectedCards(),
        hand: _hand,
      );

  @override
  bool _canPlaySelected(final PlayerSnapshot snapshot) =>
      _playController.canPlaySelected(
        snapshot: snapshot,
        humanId: _humanId,
        hand: _hand,
        selectedCards: _selectedCards(),
        schupfAckPending: _schupfAckPending,
      );

  @override
  bool _canPlayAny(final PlayerSnapshot snapshot) => _playController.canPlayAny(
    snapshot: snapshot,
    humanId: _humanId,
    hand: _hand,
    schupfAckPending: _schupfAckPending,
  );

  @override
  bool _canPass(final PlayerSnapshot snapshot) => _playController.canPass(
    snapshot: snapshot,
    humanId: _humanId,
    hand: _hand,
    schupfAckPending: _schupfAckPending,
  );

  @override
  void _showSnack(final String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
