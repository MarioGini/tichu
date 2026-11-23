/// `TurnScorer` weight overrides for A/B tests of the heuristic in the
/// headless runner (`--heuristic=`, `--opponent-heuristic=`,
/// `--shadow-heuristics=`). The app uses [latest], the heuristic as written.
///
/// The heuristic's rules are unconditional. Rules that measured worthless or
/// harmful were deleted from the code (2026-11-17, see
/// `lib/agents/ai_strategy.md`); to compare against the heuristic before
/// that, build the headless runner from commit 92aed27.
class HeuristicOptions {
  /// `PolicyWeights` overrides by field name.
  final Map<String, double> weights;

  const HeuristicOptions({this.weights = const <String, double>{}});

  /// The heuristic as written.
  static const latest = HeuristicOptions();

  /// Parses a comma list: `latest` (optional) and `weight:value` to override
  /// a `TurnScorer` weight, e.g. `latest,lowLeadPreference:4`.
  factory HeuristicOptions.parse(final String spec) {
    final weights = <String, double>{};
    for (final raw in spec.split(',')) {
      final token = raw.trim();
      if (token.isEmpty || token == 'latest') continue;
      final colon = token.indexOf(':');
      final value = colon > 0
          ? double.tryParse(token.substring(colon + 1))
          : null;
      if (value == null) {
        throw ArgumentError('Invalid heuristic spec: $token');
      }
      weights[token.substring(0, colon)] = value;
    }
    return HeuristicOptions(weights: weights);
  }

  @override
  String toString() => weights.isEmpty ? 'latest' : 'weights=$weights';
}
