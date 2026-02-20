part of '../game_screen.dart';

mixin _GameScreenHelpers on _GameScreenBindings {
  void _handleTurnEffects(final TichuTurn? previous, final TichuTurn? current) {
    if (current == null || previous == current) return;
    if (current.type == TurnType.dog) {
      unawaited(SoundEffects.playDog());
    } else if (current.type == TurnType.bomb) {
      unawaited(SoundEffects.playBomb());
      _triggerBombAnimation();
    }
  }

  void _maybeAutoConfirmOpponentTurn(final PlayerSnapshot snapshot) {
    if (!snapshot.opponentAwaitingConfirmation) return;
    final pendingPlayer = snapshot.pendingOpponentPlayerId;
    if (pendingPlayer == null) return;
    if (_isSelfManual && pendingPlayer == _humanId) return;

    final pendingKey = [
      snapshot.gameId,
      pendingPlayer,
      snapshot.pendingOpponentPass.toString(),
      snapshot.pendingOpponentCards.map((final card) => card.hashCode).join(','),
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

  void _maybeAutoPass(final PlayerSnapshot snapshot) {
    if (!_isSelfManual) return;
    if (!_autoPassEnabled) return;
    if (snapshot.phase != GamePhase.play) return;
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
      if (current.currentPlayerId != _humanId) return;
      if (_canPlayAny(current)) return;
      unawaited(_pass());
    });
  }

  void _maybeAutoSelectFinisher(final PlayerSnapshot snapshot) {
    if (!_isSelfManual) return;
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
    unawaited(_bombController.forward(from: 0));
  }

  @override
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
  TichuTurn? _resolveSelectedTurn(final PlayerSnapshot snapshot) => _playController.resolveSelectedTurn(
      snapshot: snapshot,
      selectedCards: _selectedCards(),
      hand: _hand,
    );

  bool _canPlaySelected(final PlayerSnapshot snapshot) => _playController.canPlaySelected(
      snapshot: snapshot,
      humanId: _humanId,
      hand: _hand,
      selectedCards: _selectedCards(),
      schupfAckPending: _schupfAckPending,
    );

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

  bool _canEnableBomb(final PlayerSnapshot snapshot) => _playController.canEnableBomb(
      snapshot: snapshot,
      humanId: _humanId,
      hand: _hand,
    );

  @override
  void _showSnack(final String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
