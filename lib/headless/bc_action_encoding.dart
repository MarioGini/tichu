part of 'headless.dart';

/// Legal-action enumeration and encoding for play-phase bc-jsonl rows.
extension _BcActionEncoding on _BcTransitionWriter {
  /// Encode action features for every legal play (plus pass when legal) and
  /// return them together with the index of the chosen action. Returns null
  /// when the chosen action cannot be located among the enumerated legal
  /// actions (defensive: should not happen in the play phase).
  ({List<List<double>> features, int chosenIndex, int shadowIndex})?
  _legalPlayActionFeatures({
    required final GameSnapshot snapshot,
    required final GameAction chosen,
    final GameAction? shadow,
  }) {
    final hand = List<Card>.from(
      snapshot.hands[chosen.playerId] ?? const <Card>[],
    );
    final legalTurns = LegalPlayGuard.filterMoveGeneratorTurns(
      deck: snapshot.deck,
      hand: hand,
      moveGeneratorTurns: generateLegalTurns(snapshot.deck, hand),
    );
    final encoder = FeatureEncoder(
      snapshot: snapshot,
      playerId: chosen.playerId,
    );
    final canPass = LegalPlayGuard.canPass(deck: snapshot.deck, hand: hand);

    final features = <List<double>>[];
    var chosenIndex = -1;
    var shadowIndex = -1;

    final chosenKey = chosen is PlayTurnAction ? _cardKey(chosen.cards) : null;
    final shadowKey = shadow is PlayTurnAction ? _cardKey(shadow.cards) : null;
    for (final turn in legalTurns) {
      final feat = encoder.actionFeatures(turn);
      final key = _cardKey(turn.cards);
      if (chosenIndex < 0 && chosenKey != null && key == chosenKey) {
        chosenIndex = features.length;
      }
      if (shadowIndex < 0 && shadowKey != null && key == shadowKey) {
        shadowIndex = features.length;
      }
      features.add(feat);
    }

    if (canPass) {
      final passFeat = encoder.actionFeatures(
        TichuTurn(TurnType.none, const <Card>[]),
        isPass: true,
      );
      if (chosenIndex < 0 && chosen is PassAction) {
        chosenIndex = features.length;
      }
      if (shadowIndex < 0 && shadow is PassAction) {
        shadowIndex = features.length;
      }
      features.add(passFeat);
    }

    if (chosenIndex < 0) return null;
    return (
      features: features,
      chosenIndex: chosenIndex,
      shadowIndex: shadowIndex,
    );
  }

  String _describe(final GameAction action) {
    if (action is PassAction) return 'pass';
    if (action is! PlayTurnAction) return action.runtimeType.toString();
    final cards = [for (final c in action.cards) c.face.name]..sort();
    return cards.join('+');
  }

  /// Order-independent identity of a card set (phoenix matches by face, so
  /// its assigned value does not matter).
  String _cardKey(final List<Card> cards) {
    final slots = [for (final c in cards) cardSlot(c)]..sort();
    return slots.join(',');
  }
}
