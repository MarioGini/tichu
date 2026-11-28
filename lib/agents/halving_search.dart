import 'dart:math';

/// Outcome of [sequentialHalving].
class HalvingResult {
  /// The action to play (the incumbent unless a challenger beat it).
  final int pick;

  /// Mean value of each action over the worlds it was evaluated in (null:
  /// never evaluated or dropped because a playout got stuck).
  final List<double?> means;

  /// Worlds each action was evaluated in.
  final List<int> samples;

  /// Paired mean advantage of [pick] over the incumbent and its standard
  /// error (0 and 0 when the incumbent is kept without a challenger).
  final double advantage;
  final double standardError;

  /// Evaluations spent.
  final int evaluations;

  const HalvingResult({
    required this.pick,
    required this.means,
    required this.samples,
    required this.advantage,
    required this.standardError,
    required this.evaluations,
  });
}

/// `values[i][j]`: the value of `actions[j]` in world `worlds[i]` (null =
/// stuck). Every action sees the same worlds, so their difference is free
/// of the luck of the deal (paired, as tichuengine.com's "paired
/// per-universe diff vs incumbent"). One call per halving round, so a
/// driver can spread the worlds over workers.
typedef WorldEvaluator = Future<List<List<double?>>> Function(
  List<int> worlds,
  List<int> actions,
);

/// Sequential halving over [count] candidate actions with a fixed
/// [budget] of evaluations (action x world), as in Gumbel AlphaZero: every
/// round gives each surviving action the same new worlds, then keeps the
/// better half by `mean + priorWeight * prior`, until the [incumbent] (the
/// policy's move, which always survives) and one challenger are left. The
/// rest of the budget goes to that pair.
///
/// Compared with rolling every action out in the same few worlds, the
/// budget flows to the moves that are still in contention: with 12
/// candidates and 96 evaluations the final pair gets ~30 worlds instead of
/// 8.
///
/// The challenger replaces the incumbent only if its paired mean advantage
/// exceeds [margin] and [minZ] standard errors. [prior] (one per action,
/// e.g. the net's Q in points) breaks near-ties toward the net while the
/// samples are few; with [priorWeight] 0 only the samples count.
Future<HalvingResult> sequentialHalving({
  required int count,
  required int incumbent,
  required int budget,
  required WorldEvaluator evaluate,
  List<double>? prior,
  double priorWeight = 0,
  double margin = 0,
  double minZ = 0,
}) async {
  if (count < 1 || incumbent < 0 || incumbent >= count) {
    throw ArgumentError('incumbent $incumbent out of $count actions');
  }
  // values[action][k]: value in the k-th world this action saw. Survivors
  // have all seen the same worlds 0..world-1.
  final values = [for (var a = 0; a < count; a++) <double>[]];
  final alive = [for (var a = 0; a < count; a++) a];
  var world = 0;
  var spent = 0;

  // Plays [worlds] new worlds for every survivor; drops actions that got
  // stuck (the incumbent never is, or the comparison is off).
  Future<void> sample(int worlds) async {
    final asked = List.of(alive);
    final rows = await evaluate([
      for (var w = 0; w < worlds; w++) world + w,
    ], asked);
    spent += worlds * asked.length;
    for (final row in rows) {
      final stuck = <int>[];
      for (var i = 0; i < asked.length; i++) {
        // Dropped earlier in this batch.
        if (!alive.contains(asked[i])) continue;
        final v = row[i];
        if (v == null) {
          stuck.add(asked[i]);
        } else {
          values[asked[i]].add(v);
        }
      }
      world++;
      if (stuck.contains(incumbent)) {
        // No paired comparison without the incumbent: keep it alone.
        alive.removeWhere((a) => a != incumbent);
        return;
      }
      // A survivor has a value for every world so far, so all survivors
      // stay paired world by world.
      alive.removeWhere(stuck.contains);
    }
  }

  double mean(int a) => values[a].isEmpty
      ? 0
      : values[a].reduce((x, y) => x + y) / values[a].length;
  double score(int a) => mean(a) + (prior == null ? 0 : priorWeight * prior[a]);

  final rounds = max(1, (log(count) / ln2).ceil());
  while (alive.length > 2 && budget - spent >= alive.length) {
    final per = max(1, budget ~/ (rounds * alive.length));
    await sample(min(per, (budget - spent) ~/ alive.length));
    if (alive.length <= 2) break;
    final keep = (alive.length / 2).ceil().clamp(2, alive.length);
    final ranked = alive.where((a) => a != incumbent).toList()
      ..sort((a, b) => score(b).compareTo(score(a)));
    alive
      ..clear()
      ..add(incumbent)
      ..addAll(ranked.take(keep - 1))
      ..sort();
  }
  if (alive.length == 2 && budget - spent >= 2) {
    await sample((budget - spent) ~/ 2);
  }

  final means = <double?>[
    for (var a = 0; a < count; a++)
      if (values[a].isEmpty) null else mean(a),
  ];
  final samples = [for (final v in values) v.length];
  var pick = incumbent;
  var advantage = 0.0;
  var standardError = 0.0;
  for (final a in alive) {
    if (a == incumbent) continue;
    final (d, se) = _pairedDiff(values[a], values[incumbent]);
    final significant = minZ <= 0 || d > minZ * se;
    if (d > margin && significant && d > advantage) {
      pick = a;
      advantage = d;
      standardError = se;
    }
  }
  return HalvingResult(
    pick: pick,
    means: means,
    samples: samples,
    advantage: advantage,
    standardError: standardError,
    evaluations: spent,
  );
}

/// Mean and standard error of `a[k] - b[k]` over the worlds both saw:
/// world k is the k-th entry of both (a survivor saw every world from the
/// first one, and the incumbent always survives).
(double, double) _pairedDiff(List<double> a, List<double> b) {
  final n = min(a.length, b.length);
  if (n == 0) return (0, 0);
  var sum = 0.0;
  var sumSq = 0.0;
  for (var k = 0; k < n; k++) {
    final d = a[k] - b[k];
    sum += d;
    sumSq += d * d;
  }
  final m = sum / n;
  if (n < 2) return (m, double.infinity);
  final variance = (sumSq - n * m * m) / (n - 1);
  return (m, variance <= 0 ? 0 : sqrt(variance / n));
}
