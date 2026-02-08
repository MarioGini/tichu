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

  void _maybeAutoConfirmAi(PlayerSnapshot snapshot) {
    if (!snapshot.aiAwaitingConfirmation) return;
    final pendingPlayer = snapshot.pendingAiPlayerId;
    if (pendingPlayer == null || pendingPlayer == _humanId) return;

    final pendingKey = [
      snapshot.gameId,
      pendingPlayer,
      snapshot.pendingAiPass.toString(),
      snapshot.pendingAiCards.map((card) => card.hashCode).join(','),
    ].join('|');

    if (_lastAutoConfirmKey == pendingKey) return;
    _lastAutoConfirmKey = pendingKey;

    final delayMs = (_aiDelaySeconds * 1000).round();
    _autoConfirmTimer?.cancel();
    _autoConfirmTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      if (_snapshot?.aiAwaitingConfirmation != true) return;
      _confirmAiTurn();
    });
  }

  void _maybeAutoPass(PlayerSnapshot snapshot) {
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
    if (snapshot.phase != GamePhase.play) return;
    if (snapshot.currentPlayerId != _humanId) return;
    if (snapshot.pendingDragonGiveBy == _humanId) return;
    if (snapshot.schupfReceipts.isNotEmpty) return;
    if (_schupfAckPending) return;
    if (_selectedIndexes.isNotEmpty) return;
    if (_hand.isEmpty) return;

    final updated = _turnHandler.handleTurn(
      snapshot.deck,
      List<Card>.from(_hand),
      CardFace.none,
      hand: _hand,
    );
    if (updated.turn == TichuTurn.InvalidTurn()) {
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
  TichuTurn? _resolveSelectedTurn(
    PlayerSnapshot snapshot,
  ) {
    final selected = _selectedCards();
    if (selected.isEmpty) {
      return null;
    }

    final selectedTurn = getTurn(List<Card>.from(selected));
    if (selectedTurn == TichuTurn.InvalidTurn()) {
      return null;
    }
    final updated = _turnHandler.handleTurn(
      snapshot.deck,
      List<Card>.from(selected),
      CardFace.none,
      hand: _hand,
    );
    if (updated.turn == TichuTurn.InvalidTurn()) {
      return null;
    }

    return selectedTurn;
  }

  bool _canPlaySelected(PlayerSnapshot snapshot) {
    if (snapshot.phase != GamePhase.play) return false;
    if (snapshot.pendingDragonGiveBy == _humanId) return false;
    if (snapshot.currentPlayerId != _humanId) return false;
    if (snapshot.schupfReceipts.isNotEmpty) return false;
    if (_schupfAckPending) return false;
    if (_selectedIndexes.isEmpty) return false;
    return _resolveSelectedTurn(snapshot) != null;
  }

  bool _canPlayAny(PlayerSnapshot snapshot) {
    if (snapshot.phase != GamePhase.play) return false;
    if (snapshot.pendingDragonGiveBy == _humanId) return false;
    if (snapshot.currentPlayerId != _humanId) return false;
    if (snapshot.schupfReceipts.isNotEmpty) return false;
    if (_schupfAckPending) return false;

    final legalTurns = generateLegalTurns(snapshot.deck, _hand);
    for (final turn in legalTurns) {
      final updated = _turnHandler.handleTurn(
        snapshot.deck,
        List<Card>.from(turn.cards),
        CardFace.none,
        hand: _hand,
      );
      if (updated.turn != TichuTurn.InvalidTurn()) {
        return true;
      }
    }
    return false;
  }

  bool _canEnableBomb(PlayerSnapshot snapshot) {
    if (snapshot.phase != GamePhase.play) return false;
    if (snapshot.pendingDragonGiveBy == _humanId) return false;
    if (!hasBombInHand(_hand)) return false;
    final isHumanTurn = snapshot.currentPlayerId == _humanId;
    final deckType = snapshot.deck.turn.type;
    if (!isHumanTurn &&
        (deckType == TurnType.empty || deckType == TurnType.none)) {
      return false;
    }
    return true;
  }

  @override
  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
