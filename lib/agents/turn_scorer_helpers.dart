part of 'turn_scorer.dart';

/// Trump-response bonuses and table predicates used by [TurnScorer].
extension _ScorerHelpers on TurnScorer {
  double _phoenixTrumpLeadScore({
    required final GameSnapshot snapshot,
    required final String playerId,
    required final TichuTurn play,
    required final DeckState deck,
    required final List<Card> hand,
    required final bool opponentTichuNearFinishWinning,
  }) {
    if (play.type != TurnType.single || play.cards.isEmpty) {
      return 0;
    }
    if (deck.turn.type != TurnType.single || deck.turn.cards.isEmpty) {
      return 0;
    }
    if (play.cards.first.face != CardFace.phoenix) {
      return 0;
    }

    if (!CardKnowledge.of(snapshot, playerId).dragonPlayed) {
      return 0;
    }

    final table = TableRelationships(snapshot, playerId);
    final currentWinnerId = deck.currentWinner.isNotEmpty
        ? deck.currentWinner
        : snapshot.lastPlayedBy;
    if (currentWinnerId != null && table.isPartner(currentWinnerId)) {
      return 0;
    }

    var bonus = weights.phoenixTrumpLeadCapture;
    final topCard = deck.turn.cards.first;
    if (topCard.face == CardFace.ace) {
      bonus += weights.phoenixTrumpOnAceBonus;
    }
    if (opponentTichuNearFinishWinning) {
      bonus += weights.phoenixTrumpAgainstNearFinishBonus;
    }
    return bonus;
  }

  double _naturalTrumpResponseScore({
    required final TichuTurn play,
    required final DeckState deck,
    required final List<Card> hand,
  }) {
    if (play.type != TurnType.single || play.cards.isEmpty) {
      return 0;
    }
    if (deck.turn.type != TurnType.single || deck.turn.cards.isEmpty) {
      return 0;
    }

    final selectedFace = play.cards.first.face;
    final hasPhoenixInHand = hand.any(
      (final card) => card.face == CardFace.phoenix,
    );
    final aceCount = hand
        .where((final card) => card.face == CardFace.ace)
        .length;
    final hasNaturalWinningAce = hand.any(
      (final card) => card.face == CardFace.ace && card.value > deck.turn.value,
    );

    if (selectedFace == CardFace.phoenix && hasNaturalWinningAce) {
      return -weights.preserveFlexibleTrump;
    }

    if (selectedFace == CardFace.ace && hasPhoenixInHand) {
      var bonus = weights.preferNaturalTrumpResponse;
      if (aceCount >= 2) {
        bonus += weights.preserveFlexibleTrump;
      }
      return bonus;
    }

    return 0;
  }

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

  bool _opponentTichuNearFinish(
    final GameSnapshot snapshot,
    final String playerId,
  ) {
    final table = TableRelationships(snapshot, playerId);
    for (final player in table.opponents) {
      final call = snapshot.scoreState.tichuCalls[player.id] ?? TichuCall.none;
      if (call == TichuCall.none) continue;
      final count = (snapshot.hands[player.id] ?? const <Card>[]).length;
      if (count > 0 && count <= 2) {
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

  bool _partnerCalledTichu(final GameSnapshot snapshot, final String playerId) {
    final partnerId = TableRelationships(snapshot, playerId).partnerId!;
    final call = snapshot.scoreState.tichuCalls[partnerId] ?? TichuCall.none;
    return call != TichuCall.none;
  }

  bool _opponentCalledTichu(
    final GameSnapshot snapshot,
    final String playerId,
  ) {
    final table = TableRelationships(snapshot, playerId);
    for (final player in table.opponents) {
      final call = snapshot.scoreState.tichuCalls[player.id] ?? TichuCall.none;
      if (call != TichuCall.none) {
        return true;
      }
    }
    return false;
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
