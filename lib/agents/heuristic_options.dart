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

  /// Parses `latest`, `legacy`, or a comma list of enabled rules
  /// (`support,announce,strict`); an empty list means [legacy].
  factory HeuristicOptions.parse(final String spec) {
    if (spec == 'latest') return latest;
    final on = spec
        .split(',')
        .map((final s) => s.trim())
        .where((final s) => s.isNotEmpty && s != 'legacy')
        .toSet();
    const known = {
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
    };
    final plan = on.contains('plan');
    final unknown = on.difference(known);
    if (unknown.isNotEmpty) {
      throw ArgumentError('Unknown heuristic options: $unknown');
    }
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
    );
  }

  @override
  String toString() =>
      'support=$supportPartnerTichu guard=$guardPartnerTichu announce=$announceBeforeSchupf '
      'strict=$strictTichu plan=$planPlay';
}
