import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/scoring/score_state.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// How much is at stake in a play decision, for spending rollout labels
/// (`headless --stakes-rollouts`).
///
/// Measured on v7 vs v6: most of the edge comes from going out first
/// (double wins, Tichu success) and finishing last swings ~±36 card points;
/// the endgame, play around (Grand) Tichu calls, opponents close to going
/// out and leads are where learning still moves, quiet middle-game following
/// decisions no longer improve (their label noise dominates).
enum RolloutStakes {
  /// The race to go out: someone is out, a player other than the actor has
  /// at most 3 cards, or the actor has at most 5 ([StakesReason.race]).
  high,

  /// Middle game with a (Grand) Tichu caller still in, a lead or a trick
  /// worth at least 20 points.
  mid,

  /// Everything else: a quiet middle-game decision.
  low,
}

/// Why a decision is not low stakes (several can hold at once).
enum StakesReason {
  /// A player who called Tichu / Grand Tichu is still in the round.
  call,

  /// Someone is already out (double-win race, avoiding last).
  someoneOut,

  /// An opponent has at most 3 cards left.
  opponentClose,

  /// The partner has at most 3 cards left.
  partnerClose,

  /// The deciding player has at most 5 cards left.
  endgame,

  /// The trick on the table is worth at least 20 points.
  richTrick,

  /// Leading (empty table).
  lead;

  /// The reasons that make a decision [RolloutStakes.high].
  static const Set<StakesReason> race = {
    someoneOut,
    opponentClose,
    partnerClose,
    endgame,
  };
}

/// The [StakesReason]s that hold for [playerId] deciding in [snapshot].
///
/// Uses public information only (card counts, calls, finish order, trick
/// points, the table), the same kind the feature encoder sees.
Set<StakesReason> stakesReasons(
  final GameSnapshot snapshot,
  final String playerId,
) {
  final reasons = <StakesReason>{};
  final score = snapshot.scoreState;
  final finished = score.finishOrder.toSet();
  final mySeat = snapshot.players
      .firstWhere((final p) => p.id == playerId)
      .seat;
  for (final p in snapshot.players) {
    final out = finished.contains(p.id);
    final call = score.tichuCalls[p.id] ?? TichuCall.none;
    if (call != TichuCall.none && !out) reasons.add(StakesReason.call);
    if (p.id == playerId || out) continue;
    final count = snapshot.hands[p.id]?.length ?? 0;
    if (count == 0 || count > 3) continue;
    reasons.add(
      p.seat % 2 == mySeat % 2
          ? StakesReason.partnerClose
          : StakesReason.opponentClose,
    );
  }
  if (finished.isNotEmpty) reasons.add(StakesReason.someoneOut);
  if ((snapshot.hands[playerId]?.length ?? 0) <= 5) {
    reasons.add(StakesReason.endgame);
  }
  if (snapshot.trickPoints >= 20) reasons.add(StakesReason.richTrick);
  final turn = snapshot.deck.turn.type;
  if (turn == TurnType.empty || turn == TurnType.none || turn == TurnType.dog) {
    reasons.add(StakesReason.lead);
  }
  return reasons;
}

/// The stakes class of a set of [stakesReasons].
RolloutStakes stakesOf(final Set<StakesReason> reasons) {
  if (reasons.any(StakesReason.race.contains)) return RolloutStakes.high;
  return reasons.isEmpty ? RolloutStakes.low : RolloutStakes.mid;
}

/// The stakes class of [playerId] deciding in [snapshot].
RolloutStakes classifyStakes(
  final GameSnapshot snapshot,
  final String playerId,
) => stakesOf(stakesReasons(snapshot, playerId));

/// Label probability per stakes class
/// (`--stakes-rates=high:p,mid:p,low:p`).
class StakesRates {
  final double high;
  final double mid;
  final double low;

  const StakesRates({required this.high, required this.mid, required this.low});

  /// Default rates for a uniform base rate (`--rollout-rate`), chosen so that
  /// the expected number of labelled decisions per match stays about the same
  /// as with the uniform rate (measured class shares of labellable decisions
  /// high 52 %, mid 30 %, low 18 %; see rl/README.md "Stakes-weighted rollout
  /// labels"). At the loop's 0.5: high 0.7, mid 0.35, low 0.15.
  factory StakesRates.forBase(final double base) => StakesRates(
    high: (base * highFactor).clamp(0.0, 1.0),
    mid: (base * midFactor).clamp(0.0, 1.0),
    low: (base * lowFactor).clamp(0.0, 1.0),
  );

  static const highFactor = 1.4;
  static const midFactor = 0.7;
  static const lowFactor = 0.3;

  double of(final RolloutStakes stakes) => switch (stakes) {
    RolloutStakes.high => high,
    RolloutStakes.mid => mid,
    RolloutStakes.low => low,
  };

  /// Parses `high:1.0,mid:0.4,low:0.25`; a class not named keeps
  /// [fallback]'s rate. Returns null on a malformed spec.
  static StakesRates? parse(final String spec, final StakesRates fallback) {
    var high = fallback.high;
    var mid = fallback.mid;
    var low = fallback.low;
    for (final part in spec.split(',')) {
      if (part.trim().isEmpty) continue;
      final kv = part.split(':');
      if (kv.length != 2) return null;
      final p = double.tryParse(kv[1].trim());
      if (p == null || p < 0 || p > 1) return null;
      switch (kv[0].trim()) {
        case 'high':
          high = p;
        case 'mid':
          mid = p;
        case 'low':
          low = p;
        default:
          return null;
      }
    }
    return StakesRates(high: high, mid: mid, low: low);
  }

  @override
  String toString() => 'high:$high,mid:$mid,low:$low';
}
