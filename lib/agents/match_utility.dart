import 'dart:math';

/// Match-win probability and the round result it is worth, so a search can
/// maximise the chance to win the match instead of the round points.
///
/// Points are not the objective: 50 points matter little at 200 : 250 and
/// decide everything at 950 : 980. A bot that maximises points plays the
/// same at both; tichuengine.com scores its searches in match-win
/// probability for this reason ("match utility").
///
/// The model treats the rest of the match as a random walk of the score
/// difference: each round moves it by a draw with standard deviation
/// [roundStd], and the match lasts until the leader reaches the target,
/// which takes about `(target - leader) / leaderGain` more rounds. So
///
///   P(win) = Φ(lead / (roundStd · √rounds)).
///
/// The constants come from v10 self-play (150 matches, 1630 rounds): the
/// round difference has a standard deviation of 189 points, and a round
/// gives both teams together 152 points on average, so the leader gains
/// about 76 per round. A finished match is worth 1 or 0.
class MatchUtility {
  /// Standard deviation of one round's point difference.
  final double roundStd;

  /// Mean points per round for the leading team.
  final double leaderGain;

  const MatchUtility({this.roundStd = 189, this.leaderGain = 76});

  /// The probability that the team with [us] points beats the team with
  /// [them] in a match to [target]. A tie at or above the target is played
  /// on (`ScoreTracker.gameComplete`).
  double winProbability(double us, double them, int target) {
    final leader = max(us, them);
    if (leader >= target && us != them) return us > them ? 1 : 0;
    return _phi((us - them) / (roundStd * sqrt(_rounds(leader, target))));
  }

  /// d P(win) / d lead at [us] : [them], per point (always > 0).
  double slope(double us, double them, int target) {
    final leader = max(us, them);
    final s = roundStd * sqrt(_rounds(leader, target));
    final z = (us - them) / s;
    return max(exp(-z * z / 2) / (sqrt(2 * pi) * s), 1e-9);
  }

  /// A round that ends with [usRound] : [themRound] points, entering it at
  /// [us] : [them], in points of equal match value: the change in win
  /// probability divided by the slope at the entering score. Early in a
  /// match this is close to the point difference; near the end it
  /// saturates (a won match is worth no more however large the win) and
  /// steepens around the target.
  double pointsEquivalent({
    required double us,
    required double them,
    required double usRound,
    required double themRound,
    required int target,
  }) {
    final before = winProbability(us, them, target);
    final after = winProbability(us + usRound, them + themRound, target);
    return (after - before) / slope(us, them, target);
  }

  /// Rounds left until the leader at [leader] reaches [target] (at least
  /// one: a tie at the target is played on).
  double _rounds(double leader, int target) {
    final r = (target - leader) / leaderGain;
    return r < 1 ? 1 : r;
  }

  /// Standard normal CDF (Abramowitz-Stegun 7.1.26, error < 1.5e-7).
  static double _phi(double z) {
    final x = z.abs() / sqrt2;
    final t = 1 / (1 + 0.3275911 * x);
    final y =
        1 -
        (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t -
                        0.284496736) *
                    t +
                0.254829592) *
            t *
            exp(-x * x);
    return z >= 0 ? (1 + y) / 2 : (1 - y) / 2;
  }
}
