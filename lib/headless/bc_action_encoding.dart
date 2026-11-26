part of 'headless.dart';

/// Legal-action enumeration and encoding for play-phase bc-jsonl rows.
extension _BcActionEncoding on _BcTransitionWriter {
  /// Encode action features for every legal play (plus pass when legal) and
  /// return them together with the index of the chosen action. Returns null
  /// when the chosen action cannot be located among the enumerated legal
  /// actions (defensive: should not happen in the play phase).
  ({
    List<List<double>> features,
    int chosenIndex,
    int shadowIndex,
    List<String> keys,
  })?
  _legalPlayActionFeatures({
    required GameSnapshot snapshot,
    required GameAction chosen,
    GameAction? shadow,
  }) {
    final (:legalTurns, :canPass) = _decisionActions(snapshot, chosen.playerId);
    final encoder = FeatureEncoder(
      snapshot: snapshot,
      playerId: chosen.playerId,
    );

    final features = <List<double>>[];
    final keys = <String>[];
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
      keys.add(key);
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
      keys.add('pass');
    }

    if (chosenIndex < 0) return null;
    return (
      features: features,
      chosenIndex: chosenIndex,
      shadowIndex: shadowIndex,
      keys: keys,
    );
  }

  /// Index of [action] among the legal-action [keys] (-1 when absent).
  int _indexOf(List<String> keys, GameAction? action) {
    if (action is PassAction) {
      return keys.indexOf('pass');
    }
    if (action is PlayTurnAction) return keys.indexOf(_cardKey(action.cards));
    return -1;
  }

  /// Human-readable position for analysis (`--describe`): cards as rank
  /// tokens, seats relative to the actor (L = next player, P, R).
  Map<String, Object?> _describePosition(
    GameSnapshot snapshot,
    String playerId,
  ) {
    final table = TableRelationships(snapshot, playerId);
    final hand = List<Card>.from(snapshot.hands[playerId] ?? const <Card>[]);
    final ids = [
      table.playerBySeat(table.leftSeat()).id,
      table.partnerId ?? '',
      table.playerBySeat(table.rightSeat()).id,
    ];
    String rel(String? id) {
      if (id == null || id.isEmpty) return '-';
      if (id == playerId) return 'me';
      final i = ids.indexOf(id);
      return i < 0 ? '?' : const ['L', 'P', 'R'][i];
    }

    final score = snapshot.scoreState;
    final legalTurns = LegalPlayGuard.filterMoveGeneratorTurns(
      deck: snapshot.deck,
      hand: hand,
      moveGeneratorTurns: generateLegalTurns(snapshot.deck, hand),
    );
    return {
      'hand': _tokens(hand),
      'trick': _tokens(snapshot.deck.turn.cards),
      'trick_type': snapshot.deck.turn.type.name,
      'trick_points': snapshot.trickPoints,
      'winner': rel(
        snapshot.deck.currentWinner.isNotEmpty
            ? snapshot.deck.currentWinner
            : null,
      ),
      'counts': [
        for (final id in ids) (snapshot.hands[id] ?? const <Card>[]).length,
      ],
      'hands': [
        for (final id in ids) _tokens(snapshot.hands[id] ?? const <Card>[]),
      ],
      'calls': {
        for (final id in [playerId, ...ids])
          if ((score.tichuCalls[id] ?? TichuCall.none) != TichuCall.none)
            rel(id): score.tichuCalls[id]!.name,
      },
      'out': [for (final id in score.finishOrder) rel(id)],
      'wish': snapshot.activeWish == CardFace.none
          ? ''
          : _rankToken(snapshot.activeWish),
      'acts': [
        for (final t in legalTurns) _tokens(t.cards),
        if (LegalPlayGuard.canPass(deck: snapshot.deck, hand: hand)) 'pass',
      ],
    };
  }

  String _tokens(List<Card> cards) {
    final sorted = [...cards]..sort((a, b) => _order(a).compareTo(_order(b)));
    return sorted.map((c) => _rankToken(c.face)).join(' ');
  }

  int _order(Card c) => switch (c.face) {
    CardFace.dog => -1,
    CardFace.mahJong => 1,
    CardFace.phoenix => 15,
    CardFace.dragon => 16,
    _ => faceRank(c.face),
  };

  String _rankToken(CardFace face) => switch (face) {
    CardFace.dog => 'Dog',
    CardFace.mahJong => '1',
    CardFace.phoenix => 'Ph',
    CardFace.dragon => 'Dr',
    CardFace.ten => 'T',
    CardFace.jack => 'J',
    CardFace.queen => 'Q',
    CardFace.king => 'K',
    CardFace.ace => 'A',
    CardFace.none => '?',
    _ => '${faceRank(face)}',
  };

  String _describe(GameAction action) {
    if (action is PassAction) return 'pass';
    if (action is! PlayTurnAction) return action.runtimeType.toString();
    final cards = [for (final c in action.cards) c.face.name]..sort();
    return cards.join('+');
  }

  /// Order-independent identity of a card set (phoenix matches by face, so
  /// its assigned value does not matter).
  String _cardKey(List<Card> cards) {
    final slots = [for (final c in cards) cardSlot(c)]..sort();
    return slots.join(',');
  }
}

/// The legal actions of [playerId]'s play-phase turn, in the order the net
/// scores them: the wish-filtered legal turns (+ pass when legal).
({List<TichuTurn> legalTurns, bool canPass}) _decisionActions(
  GameSnapshot snapshot,
  String playerId,
) {
  final hand = List<Card>.from(snapshot.hands[playerId] ?? const <Card>[]);
  return (
    legalTurns: LegalPlayGuard.filterMoveGeneratorTurns(
      deck: snapshot.deck,
      hand: hand,
      moveGeneratorTurns: generateLegalTurns(snapshot.deck, hand),
    ),
    canPass: LegalPlayGuard.canPass(deck: snapshot.deck, hand: hand),
  );
}
