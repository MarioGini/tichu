import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/match_utility.dart';

void main() {
  const model = MatchUtility();

  test('an even score is a coin flip, a lead is worth more', () {
    expect(model.winProbability(0, 0, 1000), closeTo(0.5, 1e-6));
    expect(model.winProbability(300, 100, 1000), greaterThan(0.6));
    expect(
      model.winProbability(300, 100, 1000) +
          model.winProbability(100, 300, 1000),
      closeTo(1, 1e-6),
    );
  });

  test('a finished match is won or lost; a tie at the target plays on', () {
    expect(model.winProbability(1010, 900, 1000), 1);
    expect(model.winProbability(900, 1010, 1000), 0);
    expect(model.winProbability(1000, 1000, 1000), closeTo(0.5, 1e-6));
  });

  test('early in a match the points-equivalent is the point difference', () {
    final v = model.pointsEquivalent(
      us: 0,
      them: 0,
      usRound: 60,
      themRound: 40,
      target: 1000,
    );
    // Slightly more: 60 points bring the leader closer to the target.
    expect(v, closeTo(20, 1.5));
  });

  test('near the end a large win is worth no more than a sure win', () {
    double v(double us) => model.pointsEquivalent(
      us: 950,
      them: 700,
      usRound: us,
      themRound: 100 - us,
      target: 1000,
    );
    // 60 : 40 already ends the match won; 100 : 0 adds nothing.
    expect(v(100), closeTo(v(60), 1e-9));
    // Below that, every point still counts, in order.
    expect(v(0), lessThan(v(30)));
    expect(v(30), lessThan(v(60)));
  });

  test('near a decided match the tails stay accurate (no noise)', () {
    // 990 : 40 is z ~ 5: P(loss) ~ 3e-7, below the absolute error of a
    // plain normal approximation. Each further point lost must still cost a
    // little more, smoothly.
    double v(double them) => model.pointsEquivalent(
      us: 990,
      them: 40,
      usRound: 0,
      themRound: them,
      target: 1000,
    );
    final points = [
      for (final t in [5.0, 10.0, 20.0, 40.0]) v(t),
    ];
    for (var i = 1; i < points.length; i++) {
      expect(points[i], lessThan(points[i - 1]));
    }
    // Losing 10 points costs a bit more than 10 (the slope steepens as the
    // lead shrinks), not hundreds.
    expect(points[1], inInclusiveRange(-15, -10));
  });

  test('the slope is positive everywhere', () {
    for (final (us, them) in [(0, 0), (900, 100), (100, 900), (990, 990)]) {
      expect(model.slope(us.toDouble(), them.toDouble(), 1000), greaterThan(0));
    }
  });
}
