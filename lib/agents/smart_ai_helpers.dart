part of 'smart_ai_agent.dart';

extension _HeuristicHelpers on SmartAiAgent {
  /// Plan-play moves decided by the situation (see [PlanPlay]).
  GameAction? _planPlay(
    final GameSnapshot snapshot,
    final DeckState deck,
    final List<Card> hand,
    final TableRelationships table,
    final List<TichuTurn> legalTurns, {
    required final bool isLeading,
  }) {
    // A partner who called and is winning the trick: never overtake.
    final partnerId = table.partnerId;
    final winnerId = deck.currentWinner.isNotEmpty
        ? deck.currentWinner
        : snapshot.lastPlayedBy;
    if (!isLeading &&
        partnerId != null &&
        winnerId == partnerId &&
        (snapshot.scoreState.tichuCalls[partnerId] ?? TichuCall.none) !=
            TichuCall.none &&
        LegalPlayGuard.canPass(deck: deck, hand: hand)) {
      return PassAction(playerId: playerId);
    }
    if (!isLeading) return null;
    final lead = PlanPlay.lead(
      snapshot: snapshot,
      playerId: playerId,
      plays: legalTurns,
      hand: hand,
      table: table,
      opponentOneCard: options.planLead || options.leadOpponentOneCard,
      feedPartner: options.planLead || options.feedPartner,
      sureFirst: options.planLead || options.sureFirst,
    );
    return lead == null ? null : _buildPlayAction(snapshot, lead, deck, hand);
  }

  /// The cheapest play in [plays] of the same type and length as [selected]
  /// (lowest rank sum; Phoenix and Dragon count as the most expensive
  /// cards). Only multi-card, non-bomb combinations are swapped: for singles
  /// the scorer's choice (which card to split off) matters more than rank.
  TichuTurn _cheapestEquivalent(
    final TichuTurn selected,
    final List<TichuTurn> plays,
  ) {
    if (selected.cards.length < 2 || selected.type == TurnType.bomb) {
      return selected;
    }
    int cost(final TichuTurn t) => t.cards.fold(
      0,
      (final sum, final c) =>
          sum +
          switch (c.face) {
            CardFace.phoenix => 15,
            CardFace.dragon => 16,
            _ => Card.getValue(c.face).round(),
          },
    );
    var best = selected;
    var bestCost = cost(selected);
    for (final t in plays) {
      if (t.type != selected.type || t.cards.length != selected.cards.length) {
        continue;
      }
      final c = cost(t);
      if (c < bestCost) {
        best = t;
        bestCost = c;
      }
    }
    return best;
  }

  int _cardsOf(final GameSnapshot snapshot, final String? id) =>
      id == null ? 0 : (snapshot.hands[id] ?? const <Card>[]).length;

  TichuTurn? _bombForValuableTrick(
    final GameSnapshot snapshot,
    final DeckState deck,
    final List<TichuTurn> plays,
    final TableRelationships table,
  ) {
    if (deck.turn.type == TurnType.empty || deck.turn.type == TurnType.none) {
      return null;
    }
    final winnerId = deck.currentWinner.isNotEmpty
        ? deck.currentWinner
        : snapshot.lastPlayedBy;
    if (winnerId == null || !table.isOpponent(winnerId)) return null;
    // (Bombing an opponent's Dragon gains nothing: a Dragon trick is given
    // to us anyway.)
    if (snapshot.trickPoints < 25) return null;
    final bombs = plays.where((final t) => t.type == TurnType.bomb).toList()
      ..sort((final a, final b) => a.value.compareTo(b.value));
    return bombs.isEmpty ? null : bombs.first;
  }

  bool _holdBackForPartnerTichu(
    final GameSnapshot snapshot,
    final TableRelationships table,
  ) {
    if (!options.supportPartnerTichu && !options.guardPartnerTichu) {
      return false;
    }
    final partnerId = table.partnerId;
    if (partnerId == null) return false;
    final partnerCall =
        snapshot.scoreState.tichuCalls[partnerId] ?? TichuCall.none;
    if (partnerCall == TichuCall.none) return false;
    if (snapshot.scoreState.finishOrder.isNotEmpty) return false;
    return (snapshot.hands[partnerId] ?? const <Card>[]).isNotEmpty;
  }

  List<TichuTurn> _filterLowSinglePhoenixResponses(
    final DeckState deck,
    final List<TichuTurn> plays,
  ) {
    if (deck.turn.type != TurnType.single) {
      return plays;
    }

    final kingValue = Card.getValue(CardFace.king);
    if (deck.turn.value >= kingValue) {
      return plays;
    }

    return plays.where((final turn) {
      if (turn.type != TurnType.single) {
        return true;
      }
      return !turn.cards.any((final card) => card.face == CardFace.phoenix);
    }).toList();
  }
}
