import 'package:tichu/agents/card_knowledge.dart';
import 'package:tichu/agents/hand_shape.dart';
import 'package:tichu/agents/table_relationships.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// Hand-plan aware play rules (`HeuristicOptions.planPlay`): think in "plays
/// needed to go out" (HandShape.estPlays) and in sure winners (CardKnowledge).
abstract final class PlanPlay {
  static int estPlays(final Iterable<Card> cards) =>
      HandShape.fromCards(cards).estPlays;

  static List<Card> remainingAfter(
    final List<Card> hand,
    final TichuTurn play,
  ) {
    final rest = List<Card>.from(hand);
    for (final c in play.cards) {
      final i = rest.indexWhere(
        (final h) => h.face == c.face && h.color == c.color,
      );
      if (i >= 0) rest.removeAt(i);
    }
    return rest;
  }

  /// Extra plays a move costs: change in plays-to-go-out, minus the one play
  /// it uses up. 0 = the play is a clean part of the plan; > 0 = it breaks a
  /// combo.
  static int planCost(final List<Card> hand, final TichuTurn play) =>
      estPlays(remainingAfter(hand, play)) - (estPlays(hand) - 1);

  static bool _isControl(final Card c) =>
      c.face == CardFace.ace ||
      c.face == CardFace.phoenix ||
      c.face == CardFace.dragon;

  static int _cards(final GameSnapshot s, final String? id) =>
      id == null ? 0 : (s.hands[id] ?? const <Card>[]).length;

  static int _minOpponentCards(
    final GameSnapshot s,
    final TableRelationships table,
  ) {
    var m = 99;
    for (final o in table.opponents) {
      final n = _cards(s, o.id);
      if (n > 0 && n < m) m = n;
    }
    return m;
  }

  /// Leading: a move dictated by the situation, or null.
  ///  * opponent with 1 card: lead a combo, else the highest single;
  ///  * partner with 1 card (no opponent at 1): feed them the lowest single;
  ///  * few cards left: cash sure winners before the last loser.
  static TichuTurn? lead({
    required final GameSnapshot snapshot,
    required final String playerId,
    required final List<TichuTurn> plays,
    required final List<Card> hand,
    required final TableRelationships table,
    final bool opponentOneCard = true,
    final bool feedPartner = true,
    final bool sureFirst = true,
  }) {
    if (plays.isEmpty) return null;
    final minOpp = _minOpponentCards(snapshot, table);
    final partnerCards = _cards(snapshot, table.partnerId);
    final noDog = plays.where((final t) => t.type != TurnType.dog).toList();
    final options = noDog.isNotEmpty ? noDog : plays;

    if (opponentOneCard && minOpp == 1) {
      final combos =
          options.where((final t) => t.type != TurnType.single).toList()
            ..sort((final a, final b) => b.cards.length - a.cards.length);
      if (combos.isNotEmpty) return combos.first;
      final singles = [...options]
        ..sort((final a, final b) => b.value.compareTo(a.value));
      return singles.first;
    }

    if (feedPartner && partnerCards == 1 && minOpp > 1) {
      final singles =
          options.where((final t) => t.type == TurnType.single).toList()
            ..sort((final a, final b) => a.value.compareTo(b.value));
      if (singles.isNotEmpty) return singles.first;
    }

    if (sureFirst && hand.length <= 6) {
      final knowledge = CardKnowledge.of(snapshot, playerId);
      final sure =
          options
              .where(
                (final t) =>
                    t.type != TurnType.bomb && knowledge.isUnbeatable(t),
              )
              .toList()
            ..sort(
              (final a, final b) =>
                  planCost(hand, a).compareTo(planCost(hand, b)),
            );
      // Only with exactly one losing play left: cash the winners, then go
      // out with the loser. With several losers, holding winners back to
      // regain the lead later is better.
      final losers = estPlays(hand) - sure.length;
      if (sure.isNotEmpty &&
          losers <= 1 &&
          sure.first.cards.length < hand.length) {
        return sure.first;
      }
    }
    return null;
  }

  /// Following an opponent's trick early in the round: pass when every beat
  /// would break the hand plan or burn a control on a cheap trick.
  static bool passInsteadOfDamaging({
    required final GameSnapshot snapshot,
    required final String playerId,
    required final List<TichuTurn> plays,
    required final List<Card> hand,
    required final TableRelationships table,
  }) {
    if (plays.isEmpty || hand.length < 8) return false;
    if (snapshot.trickPoints >= 10) return false;
    // Not once someone is out, and never let a Tichu caller keep a trick.
    if (snapshot.scoreState.finishOrder.isNotEmpty) return false;
    final winner = snapshot.deck.currentWinner.isNotEmpty
        ? snapshot.deck.currentWinner
        : snapshot.lastPlayedBy;
    if (winner != null &&
        (snapshot.scoreState.tichuCalls[winner] ?? TichuCall.none) !=
            TichuCall.none) {
      return false;
    }
    if (_minOpponentCards(snapshot, table) <= 3) return false;
    final knowledge = CardKnowledge.of(snapshot, playerId);
    for (final t in plays) {
      final burnsControl =
          t.cards.any(_isControl) && !knowledge.isUnbeatable(t);
      if (t.type != TurnType.bomb && planCost(hand, t) <= 0 && !burnsControl) {
        return false;
      }
    }
    return true;
  }

  /// Following an opponent's cheap single or pair early in the round: drop
  /// plays that spend a control card (Ace, Phoenix, Dragon) or a pair of
  /// Kings or Aces, unless the play is a sure winner. The trained bot passes
  /// here far more often than the heuristic and keeps these cards for the
  /// tricks that decide who goes out. Returns the remaining plays (possibly
  /// empty = pass).
  static List<TichuTurn> conserveControls({
    required final GameSnapshot snapshot,
    required final String playerId,
    required final List<TichuTurn> plays,
    required final List<Card> hand,
    required final TableRelationships table,
    required final DeckState deck,
  }) {
    if (deck.turn.type != TurnType.single && deck.turn.type != TurnType.pair) {
      return plays;
    }
    if (hand.length < 7 || snapshot.trickPoints >= 10) return plays;
    if (snapshot.scoreState.finishOrder.isNotEmpty) return plays;
    if (_minOpponentCards(snapshot, table) <= 3) return plays;
    final opponentCalled = table.opponents.any(
      (final o) =>
          (snapshot.scoreState.tichuCalls[o.id] ?? TichuCall.none) !=
          TichuCall.none,
    );
    if (opponentCalled) return plays;
    final knowledge = CardKnowledge.of(snapshot, playerId);
    bool spendsControl(final TichuTurn t) =>
        t.type != TurnType.bomb &&
        !knowledge.isUnbeatable(t) &&
        (t.cards.any(_isControl) ||
            (t.type == TurnType.pair &&
                t.cards.every((final c) => c.value >= 13)));
    return [
      for (final t in plays)
        if (!spendsControl(t)) t,
    ];
  }

  /// Keep bombs for valuable tricks or stopping an opponent close to going
  /// out; removes bombs from [plays] otherwise (if anything else remains).
  static List<TichuTurn> keepBombs({
    required final GameSnapshot snapshot,
    required final List<TichuTurn> plays,
    required final List<Card> hand,
    required final TableRelationships table,
    required final DeckState deck,
  }) {
    if (hand.length < 7) return plays;
    final dragonOnTop =
        deck.turn.type == TurnType.single &&
        deck.turn.cards.any((final c) => c.face == CardFace.dragon);
    final opponentCalled = table.opponents.any(
      (final o) =>
          (snapshot.scoreState.tichuCalls[o.id] ?? TichuCall.none) !=
          TichuCall.none,
    );
    if (dragonOnTop ||
        snapshot.trickPoints >= 20 ||
        _minOpponentCards(snapshot, table) <= 3 ||
        opponentCalled) {
      return plays;
    }
    final rest = plays.where((final t) => t.type != TurnType.bomb).toList();
    return rest.isEmpty ? plays : rest;
  }

  /// Singles that do not break the hand plan (a card out of a straight or
  /// a pair costs an extra play).
  static List<TichuTurn> cleanSingles(
    final List<TichuTurn> plays,
    final List<Card> hand,
  ) => [
    for (final t in plays)
      if (t.type != TurnType.single || planCost(hand, t) <= 0) t,
  ];
}
