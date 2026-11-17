/// Switches for A/B-testing the heuristic in the headless runner
/// (`--heuristic=`, `--opponent-heuristic=`, `--shadow-heuristics=`): rules
/// can be switched off by name and `TurnScorer` weights overridden. The app
/// uses [latest], the heuristic as written.
///
/// Rules that measured worthless or harmful were deleted from the code
/// (2026-11-17, see `lib/agents/ai_strategy.md`); to compare against the
/// heuristic before that, build the headless runner from commit 92aed27.
class HeuristicOptions {
  /// Rules switched off by name; see [rules].
  final Set<String> off;

  /// `PolicyWeights` overrides by field name.
  final Map<String, double> weights;

  const HeuristicOptions({
    this.off = const <String>{},
    this.weights = const <String, double>{},
  });

  /// The heuristic as written (nothing switched off).
  static const latest = HeuristicOptions();

  /// Rules that can be switched off with `-name`.
  static const rules = {
    'partner_pass',
    'mahjong_lead',
    'partner_finish_lead',
    'early_dog',
    'singleton_response',
    'cheap_combos',
    'guard',
  };

  /// Whether [rule] is active.
  bool on(final String rule) => !off.contains(rule);

  /// Parses a comma list: `latest` (optional), `-rule` to switch a rule off,
  /// `rule` to switch it back on, and `weight:value` to override a
  /// `TurnScorer` weight, e.g. `latest,-early_dog,lowLeadPreference:4`.
  factory HeuristicOptions.parse(final String spec) {
    final off = <String>{};
    final weights = <String, double>{};
    for (final raw in spec.split(',')) {
      final token = raw.trim();
      if (token.isEmpty || token == 'latest') continue;
      final colon = token.indexOf(':');
      if (colon > 0) {
        final value = double.tryParse(token.substring(colon + 1));
        if (value == null) {
          throw ArgumentError('Invalid heuristic weight: $token');
        }
        weights[token.substring(0, colon)] = value;
        continue;
      }
      final negative = token.startsWith('-');
      final name = negative ? token.substring(1) : token;
      if (!rules.contains(name)) {
        throw ArgumentError('Unknown heuristic rule: $name');
      }
      negative ? off.add(name) : off.remove(name);
    }
    return HeuristicOptions(off: off, weights: weights);
  }

  @override
  String toString() =>
      off.isEmpty && weights.isEmpty ? 'latest' : 'off=$off weights=$weights';
}
