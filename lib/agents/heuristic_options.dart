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

  /// Hand-plan aware play (plays-to-go-out, sure winners, bomb keeping,
  /// 1-card leads, passing instead of breaking combos); see PlanPlay.
  final bool planPlay;

  /// Plan-play parts (A/B ablation); [planPlay] enables all of them.
  final bool planLead;
  final bool planPass;
  final bool planBombs;
  final bool planScore;
  final bool planSingles;

  /// Lead rules (A/B): combo / highest single into a 1-card opponent,
  /// feed a 1-card partner, cash sure winners with one loser left, never
  /// lead the Dog after the partner is out.
  final bool leadOpponentOneCard;
  final bool feedPartner;
  final bool sureFirst;
  final bool noDogAfterPartnerOut;

  /// Don't spend Aces / Phoenix / Dragon / K-K or A-A pairs on an
  /// opponent's cheap single or pair early (learned from the trained bot).
  final bool conserveControls;

  /// Once the scorer has picked a multi-card combination, play the cheapest
  /// one of the same type and length instead (e.g. 6-6-Q-Q-Q rather than
  /// J-J-Q-Q-Q, Q-Q-Q-x-x rather than A-A-A-x-x when both beat the trick).
  /// Measured on exact rollout values: +0.3 points per decision both when
  /// leading and when following.
  final bool cheapCombos;

  /// Tactical shortcut rules switched off by name (A/B ablation); see
  /// [shortcutRules].
  final Set<String> off;

  /// TurnScorer weight overrides by `PolicyWeights` field name (A/B tests).
  final Map<String, double> weights;

  const HeuristicOptions({
    this.supportPartnerTichu = false,
    this.guardPartnerTichu = true,
    this.announceBeforeSchupf = false,
    this.strictTichu = true,
    this.planPlay = false,
    this.planLead = false,
    this.planPass = true,
    this.planBombs = true,
    this.planScore = true,
    this.planSingles = false,
    this.leadOpponentOneCard = false,
    this.feedPartner = false,
    this.sureFirst = false,
    this.noDogAfterPartnerOut = false,
    this.conserveControls = false,
    this.cheapCombos = false,
    this.off = const <String>{},
    this.weights = const <String, double>{},
  });

  static const latest = HeuristicOptions();

  /// Rules before these options existed.
  static const legacy = HeuristicOptions(
    guardPartnerTichu: false,
    strictTichu: false,
    planPass: false,
    planBombs: false,
    planScore: false,
  );

  /// Tactical shortcuts of the heuristic turn that can be disabled with
  /// `-name` in [HeuristicOptions.parse].
  static const shortcutRules = {
    'partner_pass',
    'mahjong_lead',
    'partner_finish_lead',
    'early_dog',
    'wish_pref',
    'phoenix_filter',
    'valuable_bomb',
    'singleton_response',
  };

  /// Whether the tactical shortcut [rule] is active.
  bool on(final String rule) => !off.contains(rule);

  static const _flags = {
    'support',
    'guard',
    'announce',
    'strict',
    'plan',
    'plan_lead',
    'plan_pass',
    'plan_bombs',
    'plan_score',
    'plan_singles',
    'lead_opp1',
    'feed_partner',
    'lead_sure',
    'no_dog',
    'conserve',
    'cheap_combos',
  };

  Set<String> get _enabledFlags => {
    if (supportPartnerTichu) 'support',
    if (guardPartnerTichu) 'guard',
    if (announceBeforeSchupf) 'announce',
    if (strictTichu) 'strict',
    if (planPlay) 'plan',
    if (planLead) 'plan_lead',
    if (planPass) 'plan_pass',
    if (planBombs) 'plan_bombs',
    if (planScore) 'plan_score',
    if (planSingles) 'plan_singles',
    if (leadOpponentOneCard) 'lead_opp1',
    if (feedPartner) 'feed_partner',
    if (sureFirst) 'lead_sure',
    if (noDogAfterPartnerOut) 'no_dog',
    if (conserveControls) 'conserve',
    if (cheapCombos) 'cheap_combos',
  };

  /// Parses a comma list on top of a preset: `latest` or `legacy` (the
  /// default base, so `support,announce` means legacy plus those rules).
  ///
  ///  * `name` enables a rule (`support`, `plan_lead`, `cheap_combos`, ...);
  ///  * `-name` disables a rule or a tactical shortcut ([shortcutRules]);
  ///  * `weight:value` overrides a TurnScorer weight
  ///    (`lowLeadPreference:4`).
  factory HeuristicOptions.parse(final String spec) {
    final tokens = spec
        .split(',')
        .map((final s) => s.trim())
        .where((final s) => s.isNotEmpty)
        .toList();
    final base = tokens.contains('latest') ? latest : legacy;
    final on = base._enabledFlags;
    final off = {...base.off};
    final weights = {...base.weights};
    for (final token in tokens) {
      if (token == 'latest' || token == 'legacy') continue;
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
      if (_flags.contains(name)) {
        negative ? on.remove(name) : on.add(name);
      } else if (shortcutRules.contains(name)) {
        negative ? off.add(name) : off.remove(name);
      } else {
        throw ArgumentError('Unknown heuristic options: {$name}');
      }
    }
    final plan = on.contains('plan');
    return HeuristicOptions(
      supportPartnerTichu: on.contains('support'),
      guardPartnerTichu: on.contains('guard'),
      announceBeforeSchupf: on.contains('announce'),
      strictTichu: on.contains('strict'),
      planPlay: plan,
      planLead: plan || on.contains('plan_lead'),
      planPass: plan || on.contains('plan_pass'),
      planBombs: plan || on.contains('plan_bombs'),
      planScore: plan || on.contains('plan_score'),
      planSingles: plan || on.contains('plan_singles'),
      leadOpponentOneCard: on.contains('lead_opp1'),
      feedPartner: on.contains('feed_partner'),
      sureFirst: on.contains('lead_sure'),
      noDogAfterPartnerOut: on.contains('no_dog'),
      conserveControls: on.contains('conserve'),
      cheapCombos: on.contains('cheap_combos'),
      off: off,
      weights: weights,
    );
  }

  @override
  String toString() =>
      'support=$supportPartnerTichu guard=$guardPartnerTichu announce=$announceBeforeSchupf '
      'strict=$strictTichu plan=$planPlay';
}
