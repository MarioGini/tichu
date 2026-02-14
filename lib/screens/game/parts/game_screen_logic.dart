part of '../game_screen.dart';

mixin _GameScreenHelpers on _GameScreenBindings {
  void _handleTurnEffects(TichuTurn? previous, TichuTurn? current) {
    if (current == null || previous == current) return;
    if (current.type == TurnType.dog) {
      SoundEffects.playDog();
    } else if (current.type == TurnType.bomb) {
      SoundEffects.playBomb();
      _triggerBombAnimation();
    }
  }

  void _handleRoundEffects(ScoreState? previous, ScoreState current) {
    if (!current.roundComplete) return;
    if (current.rounds.isEmpty) return;

    final previousRoundCount = previous?.rounds.length ?? 0;
    if (current.rounds.length <= previousRoundCount) return;

    final latestRound = current.rounds.last;
    if (!latestRound.isMatch) return;
    if (_lastMatchCelebrationRound == latestRound.roundNumber) return;

    _lastMatchCelebrationRound = latestRound.roundNumber;
    _triggerMatchAnimation();
  }

  void _maybeAutoConfirmOpponentTurn(PlayerSnapshot snapshot) {
    if (!snapshot.opponentAwaitingConfirmation) return;
    final pendingPlayer = snapshot.pendingOpponentPlayerId;
    if (pendingPlayer == null) return;
    if (_isSelfManual && pendingPlayer == _humanId) return;

    final pendingKey = [
      snapshot.gameId,
      pendingPlayer,
      snapshot.pendingOpponentPass.toString(),
      snapshot.pendingOpponentCards.map((card) => card.hashCode).join(','),
    ].join('|');

    if (_lastAutoConfirmKey == pendingKey) return;
    _lastAutoConfirmKey = pendingKey;

    final delayMs = (_opponentDelaySeconds * 1000).round();
    _autoConfirmTimer?.cancel();
    _autoConfirmTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      if (_snapshot?.opponentAwaitingConfirmation != true) return;
      _confirmOpponentTurn();
    });
  }

  void _maybeAutoPass(PlayerSnapshot snapshot) {
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
      _pass();
    });
  }

  void _maybeAutoSelectFinisher(PlayerSnapshot snapshot) {
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
        ..addAll(List<int>.generate(_hand.length, (index) => index));
    });
  }

  void _triggerBombAnimation() {
    setState(() {
      _showBombOverlay = true;
    });
    _bombController.forward(from: 0);
  }

  void _triggerMatchAnimation() {
    setState(() {
      _showMatchOverlay = true;
    });
    _matchController.forward(from: 0);
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

  int _compareCardsForDisplay(Card a, Card b) {
    final rankA = _displayRank(a);
    final rankB = _displayRank(b);
    final rankComparison = rankB.compareTo(rankA);
    if (rankComparison != 0) {
      return rankComparison;
    }

    final colorComparison = b.color.index.compareTo(a.color.index);
    if (colorComparison != 0) {
      return colorComparison;
    }

    return b.face.index.compareTo(a.face.index);
  }

  int _displayRank(Card card) {
    switch (card.face) {
      case CardFace.dragon:
        return 1000;
      case CardFace.phoenix:
        return 900;
      case CardFace.mahJong:
        return 0;
      case CardFace.dog:
        return -100;
      default:
        return 100 + Card.getValue(card.face).toInt();
    }
  }

  @override
  TichuTurn? _resolveSelectedTurn(PlayerSnapshot snapshot) {
    return _playController.resolveSelectedTurn(
      snapshot: snapshot,
      selectedCards: _selectedCards(),
      hand: _hand,
    );
  }

  bool _canPlaySelected(PlayerSnapshot snapshot) {
    return _playController.canPlaySelected(
      snapshot: snapshot,
      humanId: _humanId,
      hand: _hand,
      selectedCards: _selectedCards(),
      schupfAckPending: _schupfAckPending,
    );
  }

  bool _canPlayAny(PlayerSnapshot snapshot) {
    return _playController.canPlayAny(
      snapshot: snapshot,
      humanId: _humanId,
      hand: _hand,
      schupfAckPending: _schupfAckPending,
    );
  }

  @override
  bool _canPass(PlayerSnapshot snapshot) {
    return _playController.canPass(
      snapshot: snapshot,
      humanId: _humanId,
      hand: _hand,
      schupfAckPending: _schupfAckPending,
    );
  }

  bool _canEnableBomb(PlayerSnapshot snapshot) {
    return _playController.canEnableBomb(
      snapshot: snapshot,
      humanId: _humanId,
      hand: _hand,
    );
  }

  @override
  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
