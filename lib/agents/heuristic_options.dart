/// Switchable heuristic rules, so variants can be A/B-tested against each
/// other in one headless match (`--heuristic=` / `--opponent-heuristic=`).
/// The app uses [latest]: guard + strict, the best combination measured
/// against [legacy] (duplicate, 150 deals to 1000). Always passing for a
/// calling partner (`support`) and announcing before the schupf
/// (`announce`) measured slightly worse, so they are off.
class HeuristicOptions {
  /// Partner called Tichu: pass whenever allowed and never go out first.
  final bool supportPartnerTichu;

  /// Partner called Tichu: never go out ahead of them (but still beat the
  /// opponents' tricks). Weaker form of [supportPartnerTichu].
  final bool guardPartnerTichu;

  /// Call Tichu already before the exchange with a Tichu hand, so the
  /// partner passes over their best card.
  final bool announceBeforeSchupf;

  /// Hands with the Dog or 4+ unpaired low cards need one more control.
  final bool strictTichu;

  const HeuristicOptions({
    this.supportPartnerTichu = false,
    this.guardPartnerTichu = true,
    this.announceBeforeSchupf = false,
    this.strictTichu = true,
  });

  static const latest = HeuristicOptions();

  /// Rules before these options existed.
  static const legacy = HeuristicOptions(
    guardPartnerTichu: false,
    strictTichu: false,
  );

  /// Parses `latest`, `legacy`, or a comma list of enabled rules
  /// (`support,announce,strict`); an empty list means [legacy].
  factory HeuristicOptions.parse(final String spec) {
    if (spec == 'latest') return latest;
    final on = spec
        .split(',')
        .map((final s) => s.trim())
        .where((final s) => s.isNotEmpty && s != 'legacy')
        .toSet();
    const known = {'support', 'guard', 'announce', 'strict'};
    final unknown = on.difference(known);
    if (unknown.isNotEmpty) {
      throw ArgumentError('Unknown heuristic options: $unknown');
    }
    return HeuristicOptions(
      supportPartnerTichu: on.contains('support'),
      guardPartnerTichu: on.contains('guard'),
      announceBeforeSchupf: on.contains('announce'),
      strictTichu: on.contains('strict'),
    );
  }

  @override
  String toString() =>
      'support=$supportPartnerTichu guard=$guardPartnerTichu announce=$announceBeforeSchupf '
      'strict=$strictTichu';
}
