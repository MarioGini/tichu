part of 'turn_scorer.dart';

/// Table predicates and hand helpers used by [TurnScorer].
extension _ScorerHelpers on TurnScorer {
  bool _opponentLow(final GameSnapshot snapshot, final String playerId) {
    final table = TableRelationships(snapshot, playerId);
    for (final player in table.opponents) {
      final count = (snapshot.hands[player.id] ?? const <Card>[]).length;
      if (count > 0 && count < 5) {
        return true;
      }
    }
    return false;
  }

  bool _opponentAtOne(final GameSnapshot snapshot, final String playerId) {
    final table = TableRelationships(snapshot, playerId);
    for (final player in table.opponents) {
      final count = (snapshot.hands[player.id] ?? const <Card>[]).length;
      if (count == 1) {
        return true;
      }
    }
    return false;
  }

  bool _opponentTichuNearFinishWinningTrick(
    final GameSnapshot snapshot,
    final String playerId,
    final DeckState deck,
  ) {
    final table = TableRelationships(snapshot, playerId);
    final winnerId = deck.currentWinner.isNotEmpty
        ? deck.currentWinner
        : snapshot.lastPlayedBy;
    if (winnerId == null) {
      return false;
    }

    if (!table.isOpponent(winnerId)) {
      return false;
    }

    final call = snapshot.scoreState.tichuCalls[winnerId] ?? TichuCall.none;
    if (call == TichuCall.none) {
      return false;
    }
    final count = (snapshot.hands[winnerId] ?? const <Card>[]).length;
    return count > 0 && count <= 2;
  }

  /// Bombs, plus anything the unseen cards provably cannot beat.
  bool _isUnbeatableLine(final TichuTurn play, final CardKnowledge knowledge) =>
      play.type == TurnType.bomb || knowledge.isUnbeatable(play);

  int _countLowSingletons(final List<Card> hand) {
    final normalCards = hand
        .where(
          (final c) =>
              c.face != CardFace.phoenix &&
              c.face != CardFace.dog &&
              c.face != CardFace.dragon,
        )
        .toList();
    final occurrences = getOccurrenceCount(normalCards);
    var count = 0;
    for (final entry in occurrences.entries) {
      if (entry.value != 1) continue;
      final value = Card.getValue(entry.key);
      if (value <= 7) {
        count += 1;
      }
    }
    return count;
  }

  List<Card> _removePlayedCards(
    final List<Card> hand,
    final List<Card> played,
  ) {
    final remaining = List<Card>.from(hand);
    for (final card in played) {
      if (card.face == CardFace.phoenix) {
        final index = remaining.indexWhere(
          (final c) => c.face == CardFace.phoenix,
        );
        if (index != -1) {
          remaining.removeAt(index);
        }
        continue;
      }
      final index = remaining.indexWhere((final c) => c == card);
      if (index != -1) {
        remaining.removeAt(index);
      }
    }
    return remaining;
  }
}
