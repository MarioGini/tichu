import 'package:tichu/agents/card_knowledge.dart';
import 'package:tichu/agents/hand_shape.dart';
import 'package:tichu/agents/table_relationships.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// Hand-plan aware play rules (`HeuristicOptions.planPlay`), from the
/// weakness analysis in doc/heuristic_weaknesses.md: think in "plays needed
/// to go out" (HandShape.estPlays) and in sure winners (CardKnowledge).
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
  }) {
    if (plays.isEmpty) return null;
    final minOpp = _minOpponentCards(snapshot, table);
    final partnerCards = _cards(snapshot, table.partnerId);
    final noDog = plays.where((final t) => t.type != TurnType.dog).toList();
    final options = noDog.isNotEmpty ? noDog : plays;

    if (minOpp == 1) {
      final combos =
          options.where((final t) => t.type != TurnType.single).toList()
            ..sort((final a, final b) => b.cards.length - a.cards.length);
      if (combos.isNotEmpty) return combos.first;
      final singles = [...options]
        ..sort((final a, final b) => b.value.compareTo(a.value));
      return singles.first;
    }

    if (partnerCards == 1) {
      final singles =
          options.where((final t) => t.type == TurnType.single).toList()
            ..sort((final a, final b) => a.value.compareTo(b.value));
      if (singles.isNotEmpty) return singles.first;
    }

    if (hand.length <= 6) {
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
      if (sure.isNotEmpty && sure.first.cards.length < hand.length) {
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
