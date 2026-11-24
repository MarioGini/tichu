part of 'play_tactics_policy.dart';

/// Tactics that are never swapped out in tests (so not overridable).
extension PlayTacticsExtras on PlayTacticsPolicy {
  TichuTurn? selectEarlyDogLead({
    required List<TichuTurn> legalTurns,
    required bool isLeading,
  }) {
    if (!isLeading) {
      return null;
    }

    for (final turn in legalTurns) {
      if (turn.type == TurnType.dog ||
          turn.cards.any((card) => card.face == CardFace.dog)) {
        return turn;
      }
    }

    return null;
  }

  TichuTurn? selectPartnerGrandTichuDogLead({
    required String playerId,
    required GameSnapshot snapshot,
    required List<TichuTurn> legalTurns,
    required bool isLeading,
    required TableRelationships table,
  }) {
    if (!isLeading) {
      return null;
    }

    final partnerId = table.partnerId;
    if (partnerId == null) {
      return null;
    }

    final partnerCall =
        snapshot.scoreState.tichuCalls[partnerId] ?? TichuCall.none;
    if (partnerCall != TichuCall.grandTichu) {
      return null;
    }

    if (snapshot.lastPlayedBy != playerId) {
      return null;
    }

    for (final turn in legalTurns) {
      if (turn.type == TurnType.dog ||
          turn.cards.any((card) => card.face == CardFace.dog)) {
        return turn;
      }
    }

    return null;
  }

  bool opponentTichuNearFinishWinning({
    required String playerId,
    required GameSnapshot snapshot,
    required DeckState deck,
    required TableRelationships table,
  }) {
    final winnerId = deck.currentWinner.isNotEmpty
        ? deck.currentWinner
        : snapshot.lastPlayedBy;
    if (winnerId == null || winnerId == playerId) {
      return false;
    }
    if (!table.isOpponent(winnerId)) {
      return false;
    }

    final call = snapshot.scoreState.tichuCalls[winnerId] ?? TichuCall.none;
    if (call == TichuCall.none) {
      return false;
    }
    final cardsLeft = (snapshot.hands[winnerId] ?? const <Card>[]).length;
    return cardsLeft > 0 && cardsLeft <= 2;
  }

  /// When responding to a single on the deck, prefer playing a card whose face
  /// appears only once in the hand (a true singleton) so that pairs and larger
  /// combos are preserved.  Returns the lowest such singleton, or `null` if
  /// none exists (in which case the caller falls through to the scorer).
  TichuTurn? selectSingletonResponse({
    required List<TichuTurn> legalTurns,
    required DeckState deck,
    required List<Card> hand,
  }) {
    if (deck.turn.type != TurnType.single) return null;

    final singles = legalTurns.where((t) => t.type == TurnType.single).toList();
    if (singles.isEmpty) return null;

    // Count how many times each face appears in the hand (ignoring specials
    // like phoenix which can substitute for anything).
    final normalCards = hand
        .where(
          (c) =>
              c.face != CardFace.phoenix &&
              c.face != CardFace.dog &&
              c.face != CardFace.dragon,
        )
        .toList();
    final occurrences = getOccurrenceCount(normalCards);

    final hasNaturalWinningSingle = singles.any((t) {
      final face = t.cards.first.face;
      return face != CardFace.phoenix &&
          face != CardFace.dragon &&
          face != CardFace.dog;
    });

    // Filter to singles whose face is a true singleton in the hand.
    final singletonPlays = singles.where((t) {
      final face = t.cards.first.face;
      // Dragon and dog are always fine to play. Preserve phoenix when a
      // natural winning single exists, since phoenix is our most flexible
      // remaining trump-like control card.
      if (face == CardFace.dragon || face == CardFace.dog) {
        return true;
      }
      if (face == CardFace.phoenix) {
        return !hasNaturalWinningSingle;
      }
      return (occurrences[face] ?? 0) == 1;
    }).toList();

    if (singletonPlays.isEmpty) return null;

    // Pick the lowest-value singleton.
    singletonPlays.sort((a, b) => a.value.compareTo(b.value));
    return singletonPlays.first;
  }
}
