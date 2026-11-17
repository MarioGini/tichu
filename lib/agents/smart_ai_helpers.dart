part of 'smart_ai_agent.dart';

extension _HeuristicHelpers on SmartAiAgent {
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

  bool _holdBackForPartnerTichu(
    final GameSnapshot snapshot,
    final TableRelationships table,
  ) {
    if (!options.on('guard')) return false;
    final partnerId = table.partnerId;
    if (partnerId == null) return false;
    final partnerCall =
        snapshot.scoreState.tichuCalls[partnerId] ?? TichuCall.none;
    if (partnerCall == TichuCall.none) return false;
    if (snapshot.scoreState.finishOrder.isNotEmpty) return false;
    return (snapshot.hands[partnerId] ?? const <Card>[]).isNotEmpty;
  }
}
