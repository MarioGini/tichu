import 'package:tichu/agents/hand_shape.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// Hand-plan measure used by `TurnScorer`: how many plays a hand needs to go
/// out ([HandShape.estPlays]) and how many extra plays a move costs.
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
}
