part of 'headless.dart';

/// Applies actions and asserts they are legal (bots must never cheat).
extension _Legality on _HeadlessSimulator {
  GameAction _applyActionWithRecovery({
    required final GameEngine engine,
    required final GameEngineState state,
    required final GameSnapshot snapshot,
    required final GameAction selectedAction,
  }) {
    final normalizedSelectedAction = _normalizeActionForEngine(selectedAction);
    _assertActionLegal(snapshot: snapshot, action: normalizedSelectedAction);
    engine.applyAction(state, normalizedSelectedAction);
    return normalizedSelectedAction;
  }

  GameAction _normalizeActionForEngine(final GameAction action) {
    if (action is PlayTurnAction) {
      return PlayTurnAction(
        playerId: action.playerId,
        cards: List<Card>.from(action.cards),
        inputWish: action.inputWish,
      );
    }
    return action;
  }

  void _assertActionLegal({
    required final GameSnapshot snapshot,
    required final GameAction action,
  }) {
    if (action is PlayTurnAction) {
      _assertPlayActionLegal(snapshot: snapshot, action: action);
      return;
    }
    if (action is PassAction) {
      _assertPassActionLegal(snapshot: snapshot, action: action);
    }
  }

  void _assertPlayActionLegal({
    required final GameSnapshot snapshot,
    required final PlayTurnAction action,
  }) {
    if (snapshot.phase != GamePhase.play) {
      throw StateError('Illegal play action outside play phase.');
    }
    final hand = List<Card>.from(
      snapshot.hands[action.playerId] ?? const <Card>[],
    );
    if (!_handContainsAllCards(hand: hand, cards: action.cards)) {
      throw StateError('Illegal play action: cards not in hand.');
    }

    late final TichuTurn turn;
    try {
      turn = getTurn(List<Card>.from(action.cards));
    } on Exception {
      throw StateError('Illegal play action: invalid turn shape.');
    }
    if (turn.type == TurnType.none) {
      throw StateError('Illegal play action: invalid turn shape.');
    }
    // Out of turn only a bomb may be played (an interrupt).
    if (action.playerId != snapshot.currentPlayerId &&
        turn.type != TurnType.bomb) {
      throw StateError('Illegal play action by non-current player.');
    }
    if (mahJong(snapshot.deck, turn, hand)) {
      throw StateError('Illegal play action: wish must be fulfilled.');
    }
    if (!validTurn(snapshot.deck.turn, turn)) {
      throw StateError('Illegal play action: does not beat current deck turn.');
    }
  }

  void _assertPassActionLegal({
    required final GameSnapshot snapshot,
    required final PassAction action,
  }) {
    if (snapshot.phase != GamePhase.play) {
      throw StateError('Illegal pass action outside play phase.');
    }
    if (action.playerId != snapshot.currentPlayerId) {
      throw StateError('Illegal pass action by non-current player.');
    }

    final hand = List<Card>.from(
      snapshot.hands[action.playerId] ?? const <Card>[],
    );
    if (!_canPass(snapshot: snapshot, hand: hand)) {
      throw StateError('Illegal pass action for current deck/hand state.');
    }
  }

  bool _handContainsAllCards({
    required final List<Card> hand,
    required final List<Card> cards,
  }) {
    final temp = List<Card>.from(hand);
    for (final card in cards) {
      final index = temp.indexWhere((final candidate) {
        if (card.face == CardFace.phoenix) {
          return candidate.face == CardFace.phoenix;
        }
        return candidate.face == card.face && candidate.color == card.color;
      });
      if (index < 0) return false;
      temp.removeAt(index);
    }
    return true;
  }

  bool _canPass({
    required final GameSnapshot snapshot,
    required final List<Card> hand,
  }) {
    if (snapshot.deck.turn.type == TurnType.empty ||
        snapshot.deck.turn.type == TurnType.none) {
      return false;
    }
    return !mahJong(snapshot.deck, TichuTurn(TurnType.none, const []), hand);
  }
}
