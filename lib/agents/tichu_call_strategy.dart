import 'package:tichu/agents/hand_shape.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

abstract class TichuCallStrategy {
  Future<bool> shouldCallGrandTichu(GameSnapshot snapshot, String playerId);
  Future<bool> shouldCallTichu(GameSnapshot snapshot, String playerId);

  /// Tichu call before passing cards (14 cards seen, nothing exchanged yet).
  /// Calling early tells the partner to support, e.g. with a strong pass.
  Future<bool> shouldCallTichuBeforeSchupf(
    GameSnapshot snapshot,
    String playerId,
  );
}

/// The heuristic's calls: Grand Tichu when [grandStrength] reaches
/// [grandThreshold], never before the schupf, and Tichu when [tichuStrength]
/// reaches a threshold. Both thresholds are calibrated on exact
/// counterfactual call values.
class DefaultTichuCallStrategy implements TichuCallStrategy {
  /// The thresholds this strategy calls at (the calibrated constants by
  /// default; headless `--tichu-threshold` etc. for experiments).
  final double tichuThreshold;
  final double tichuThresholdVsCall;
  final double grandTichuThreshold;

  const DefaultTichuCallStrategy({
    this.tichuThreshold = strengthThreshold,
    this.tichuThresholdVsCall = strengthThresholdVsCall,
    this.grandTichuThreshold = grandThreshold,
  });

  @override
  Future<bool> shouldCallTichuBeforeSchupf(
    GameSnapshot snapshot,
    String playerId,
  ) async => false;

  @override
  Future<bool> shouldCallGrandTichu(
    GameSnapshot snapshot,
    String playerId,
  ) async =>
      grandStrength(snapshot.hands[playerId] ?? const <Card>[]) >=
      grandTichuThreshold;

  /// Call Grand Tichu at this [grandStrength]: Dragon + Phoenix, either of
  /// them with two Aces (or a bomb), or with an Ace and three Kings /
  /// Queens. A bomb alone never reaches it.
  static const double grandThreshold = 5;

  /// Grand Tichu strength of the first eight cards: Dragon and Phoenix 3,
  /// Ace 1, King and Queen 1/3, four of a kind 2, the Dog -1.
  ///
  /// A bomb wins only one lead, so it is worth about two Aces, not a
  /// Dragon plus an Ace (Aaron Fuegi's Tichu strategy article: "Consider a
  /// bomb to be worth about 1.5-2 of the 8 cards above").
  static double grandStrength(List<Card> hand) {
    final counts = <CardFace, int>{};
    for (final c in hand) {
      counts[c.face] = (counts[c.face] ?? 0) + 1;
    }
    int n(CardFace f) => counts[f] ?? 0;
    final quads = counts.entries
        .where((e) => e.value == 4 && Card.getValue(e.key) >= 2)
        .length;
    return 3.0 * n(CardFace.dragon) +
        3.0 * n(CardFace.phoenix) +
        n(CardFace.ace) +
        (n(CardFace.king) + n(CardFace.queen)) / 3 +
        2.0 * quads -
        n(CardFace.dog);
  }

  @override
  Future<bool> shouldCallTichu(GameSnapshot snapshot, String playerId) async {
    final hand = snapshot.hands[playerId] ?? const <Card>[];
    final mySeat = snapshot.players.firstWhere((q) => q.id == playerId).seat;
    // Calling against an opponent who already called rarely pays: needs a
    // stronger hand, but is not forbidden.
    final opponentCalled = snapshot.players.any(
      (p) =>
          p.id != playerId &&
          p.seat % 2 != mySeat % 2 &&
          (snapshot.scoreState.tichuCalls[p.id] ?? TichuCall.none) !=
              TichuCall.none,
    );
    return tichuStrength(hand) >=
        (opponentCalled ? tichuThresholdVsCall : tichuThreshold);
  }

  /// Calibrated on exact counterfactual call values (3,475 first-Tichu
  /// decisions, heuristic self-play): -0.1 maximises the value of calls
  /// (+3.5 pts per decision) while players call 18.6 % of the time, i.e.
  /// ~34 % of rounds per team.
  static const double strengthThreshold = -0.1;

  /// Threshold when an opponent already called Tichu (best value +1.3 pts
  /// per decision at 4.4 % calls; lower thresholds lose up to -18).
  static const double strengthThresholdVsCall = 0.5;

  /// How likely [hand] goes out first: sure trick-winners (to take the lead
  /// back) against the number of plays the hand needs to go out.
  ///
  ///   winners = Dragon 1.0 + Phoenix 0.8 + 0.7 per Ace + 1.2 per bomb
  ///             + 0.2 per King
  ///   strength = winners - 0.35 * plays-to-go-out - 0.7 if holding the Dog
  static double tichuStrength(List<Card> hand) {
    final shape = HandShape.fromCards(hand);
    double count(CardFace f) =>
        hand.where((c) => c.face == f).length.toDouble();
    final winners =
        count(CardFace.dragon) +
        0.8 * count(CardFace.phoenix) +
        0.7 * count(CardFace.ace) +
        1.2 * shape.bombs +
        0.2 * count(CardFace.king);
    return winners - 0.35 * shape.estPlays - 0.7 * count(CardFace.dog);
  }

  /// Whether [hand] is strong enough to call Tichu (no opponent call). Also
  /// used before the exchange to decide whether to keep strong cards.
  bool isTichuHand(List<Card> hand) => tichuStrength(hand) >= tichuThreshold;
}
