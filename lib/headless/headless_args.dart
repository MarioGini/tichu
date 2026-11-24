part of 'headless.dart';

class _HeadlessConfig {
  final int? seed;
  final int targetScore;
  final int? rounds;
  final int episodes;
  final int maxStepsPerEpisode;
  final String outputPath;
  final _HeadlessOutputFormat outputFormat;
  final bool showHelp;
  final bool includeTimestamps;
  final String? nnPolicyPath;
  final String? opponentPolicyPath;
  final String? opponentSchupfNetPath;
  final String? opponentTichuNetPath;
  final double epsilon;
  final bool mixed;
  final bool swapTeams;
  final int episodeOffset;
  final int? dealSeed;
  final String? tichuNetPath;
  final String? grandNetPath;
  final double callEpsilon;
  final String? schupfNetPath;
  final String? preTichuNetPath;
  final HeuristicOptions heuristic;
  final HeuristicOptions opponentHeuristic;
  final StyleBias style;
  final StyleBias opponentStyle;
  final double? preTichuStrength;
  final double? opponentPreTichuStrength;
  final bool schupfExtended;
  final bool opponentSchupfExtended;
  final bool schupfLabelExtended;
  final String? beliefNetPath;
  final double schupfEpsilon;
  final bool shadowHeuristic;
  final bool skipPlayRows;
  final bool counterfactualCalls;
  final double counterfactualRate;
  final double rolloutRate;
  final int rolloutMaxActions;
  final int rolloutWorlds;
  final double leadRolloutRate;
  final int leadWorlds;
  final double sideRolloutRate;
  final int worldsMinCards;
  final int labelMaxCards;
  final String labelSeats;
  final bool describe;
  final List<HeuristicOptions> shadowVariants;
  final bool simd;
  final double schupfRolloutRate;
  final int schupfCandidates;
  final int pimcWorlds;

  /// Endgame search for the policy / opponent team (null = off).
  final EndgameSearch? endgameSearch;
  final EndgameSearch? opponentEndgameSearch;

  const _HeadlessConfig({
    required this.seed,
    required this.targetScore,
    required this.rounds,
    required this.episodes,
    required this.maxStepsPerEpisode,
    required this.outputPath,
    required this.outputFormat,
    required this.showHelp,
    required this.includeTimestamps,
    required this.nnPolicyPath,
    required this.opponentPolicyPath,
    required this.opponentSchupfNetPath,
    required this.opponentTichuNetPath,
    required this.epsilon,
    required this.mixed,
    required this.swapTeams,
    required this.episodeOffset,
    required this.dealSeed,
    required this.tichuNetPath,
    required this.grandNetPath,
    required this.callEpsilon,
    required this.schupfNetPath,
    required this.preTichuNetPath,
    required this.heuristic,
    required this.opponentHeuristic,
    required this.style,
    required this.opponentStyle,
    required this.preTichuStrength,
    required this.opponentPreTichuStrength,
    required this.schupfExtended,
    required this.opponentSchupfExtended,
    required this.schupfLabelExtended,
    required this.beliefNetPath,
    required this.schupfEpsilon,
    required this.shadowHeuristic,
    required this.skipPlayRows,
    required this.counterfactualCalls,
    required this.counterfactualRate,
    required this.rolloutRate,
    required this.rolloutMaxActions,
    required this.rolloutWorlds,
    required this.leadRolloutRate,
    required this.leadWorlds,
    required this.sideRolloutRate,
    required this.worldsMinCards,
    required this.labelMaxCards,
    required this.labelSeats,
    required this.describe,
    required this.shadowVariants,
    required this.simd,
    required this.schupfRolloutRate,
    required this.schupfCandidates,
    required this.pimcWorlds,
    this.endgameSearch,
    this.opponentEndgameSearch,
  });
}

enum _HeadlessOutputFormat { csv, bcJsonl, summary, none }

_HeadlessConfig _parseArgs(final List<String> args) {
  int? seed;
  var targetScore = _defaultTargetScore;
  int? rounds;
  var outputPath = 'game.csv';
  var outputFormat = _HeadlessOutputFormat.csv;
  var episodes = _defaultEpisodes;
  var maxStepsPerEpisode = _defaultMaxStepsPerEpisode;
  var includeTimestamps = true;
  String? nnPolicyPath;
  String? opponentPolicyPath;
  String? opponentSchupfNetPath;
  String? opponentTichuNetPath;
  var outputProvided = false;
  var showHelp = false;
  var epsilon = 0.0;
  var mixed = false;
  var swapTeams = false;
  var episodeOffset = 0;
  int? dealSeed;
  String? tichuNetPath;
  String? grandNetPath;
  var callEpsilon = 0.0;
  String? schupfNetPath;
  String? preTichuNetPath;
  var heuristic = HeuristicOptions.latest;
  var opponentHeuristic = HeuristicOptions.latest;
  var style = StyleBias.none;
  var opponentStyle = StyleBias.none;
  double? preTichuStrength;
  double? opponentPreTichuStrength;
  var schupfExtended = false;
  var opponentSchupfExtended = false;
  var schupfLabelExtended = false;
  var schupfEpsilon = 0.0;
  var shadowHeuristic = false;
  var skipPlayRows = false;
  var counterfactualCalls = false;
  var counterfactualRate = 1.0;
  var rolloutRate = 0.0;
  var rolloutMaxActions = 12;
  var rolloutWorlds = 1;
  var leadRolloutRate = -1.0;
  var leadWorlds = 0;
  var sideRolloutRate = 0.0;
  var worldsMinCards = 0;
  var labelMaxCards = 14;
  var labelSeats = 'policy';
  var describe = false;
  var shadowVariants = const <HeuristicOptions>[];
  var simd = true;
  var schupfRolloutRate = 0.0;
  var schupfCandidates = 16;
  var pimcWorlds = 0;
  var endgameSearch = false;
  var opponentEndgameSearch = false;
  var endgameSolve = false;
  var opponentEndgameSolve = false;
  var solveBudget = 20000;
  var solveMaxCards = 10;
  var pimcSolve = false;
  var opponentPimcSolve = false;
  String? beliefNetPath;
  var endgameBelief = false;
  var opponentEndgameBelief = false;
  var pimcMaxCards = 12;
  const defaults = EndgameSearch();
  var endgameWorlds = defaults.worlds;
  var endgameMaxCards = defaults.maxCards;
  int? opponentEndgameMaxCards;
  var endgameMargin = defaults.margin;
  var endgameMaxActions = defaults.maxActions;

  for (final arg in args) {
    if (arg == '--help' || arg == '-h') {
      showHelp = true;
      continue;
    }
    if (arg.startsWith('--seed=')) {
      seed = int.tryParse(arg.split('=').last);
      continue;
    }
    if (arg.startsWith('--target-score=')) {
      targetScore = int.tryParse(arg.split('=').last) ?? _defaultTargetScore;
      continue;
    }
    if (arg.startsWith('--rounds=')) {
      final p = int.tryParse(arg.split('=').last);
      if (p != null && p > 0) rounds = p;
      continue;
    }
    if (arg.startsWith('--episodes=')) {
      final p = int.tryParse(arg.split('=').last);
      if (p != null && p > 0) episodes = p;
      continue;
    }
    if (arg.startsWith('--max-steps=')) {
      final p = int.tryParse(arg.split('=').last);
      if (p != null && p > 0) maxStepsPerEpisode = p;
      continue;
    }
    if (arg.startsWith('--format=')) {
      switch (arg.split('=').last) {
        case 'csv':
          outputFormat = _HeadlessOutputFormat.csv;
        case 'bc-jsonl':
          outputFormat = _HeadlessOutputFormat.bcJsonl;
        case 'summary':
          outputFormat = _HeadlessOutputFormat.summary;
        case 'none':
          outputFormat = _HeadlessOutputFormat.none;
      }
      continue;
    }
    if (arg == '--no-timestamps') {
      includeTimestamps = false;
      continue;
    }
    if (arg.startsWith('--output=')) {
      outputPath = arg.split('=').last;
      outputProvided = true;
      continue;
    }
    if (arg.startsWith('--epsilon=')) {
      final p = double.tryParse(arg.split('=').last);
      if (p != null && p >= 0 && p <= 1) epsilon = p;
      continue;
    }
    if (arg.startsWith('--nn-policy=')) {
      nnPolicyPath = arg.split('=').last;
      continue;
    }
    if (arg.startsWith('--opponent-tichu-net=')) {
      opponentTichuNetPath = arg.split('=').last;
      continue;
    }
    if (arg.startsWith('--opponent-schupf-net=')) {
      opponentSchupfNetPath = arg.split('=').last;
      continue;
    }
    if (arg.startsWith('--opponent-policy=')) {
      opponentPolicyPath = arg.split('=').last;
      continue;
    }
    if (arg == '--mixed') {
      mixed = true;
      continue;
    }
    if (arg == '--swap-teams') {
      swapTeams = true;
      continue;
    }
    if (arg.startsWith('--episode-offset=')) {
      final p = int.tryParse(arg.split('=').last);
      if (p != null && p >= 0) episodeOffset = p;
      continue;
    }
    if (arg.startsWith('--tichu-net=')) {
      tichuNetPath = arg.split('=').last;
      continue;
    }
    if (arg.startsWith('--grand-net=')) {
      grandNetPath = arg.split('=').last;
      continue;
    }
    if (arg.startsWith('--counterfactual-rate=')) {
      final p = double.tryParse(arg.split('=').last);
      if (p != null && p > 0 && p <= 1) counterfactualRate = p;
      continue;
    }
    if (arg.startsWith('--rollout-rate=')) {
      final p = double.tryParse(arg.split('=').last);
      if (p != null && p >= 0 && p <= 1) rolloutRate = p;
      continue;
    }
    if (arg.startsWith('--side-rollout-rate=')) {
      final p = double.tryParse(arg.split('=').last);
      if (p != null && p >= 0 && p <= 1) sideRolloutRate = p;
      continue;
    }
    if (arg.startsWith('--lead-rollout-rate=')) {
      final p = double.tryParse(arg.split('=').last);
      if (p != null && p >= 0 && p <= 1) leadRolloutRate = p;
      continue;
    }
    if (arg.startsWith('--lead-worlds=')) {
      final k = int.tryParse(arg.split('=').last);
      if (k != null && k >= 1) leadWorlds = k;
      continue;
    }
    if (arg.startsWith('--rollout-worlds=')) {
      final k = int.tryParse(arg.split('=').last);
      if (k != null && k >= 1) rolloutWorlds = k;
      continue;
    }
    if (arg.startsWith('--worlds-min-cards=')) {
      final k = int.tryParse(arg.split('=').last);
      if (k != null && k >= 0) worldsMinCards = k;
      continue;
    }
    if (arg.startsWith('--label-max-cards=')) {
      final k = int.tryParse(arg.split('=').last);
      if (k != null && k >= 1) labelMaxCards = k;
      continue;
    }
    if (arg.startsWith('--rollout-max-actions=')) {
      final p = int.tryParse(arg.split('=').last);
      if (p != null && p >= 2) rolloutMaxActions = p;
      continue;
    }
    if (arg.startsWith('--label-seats=')) {
      final v = arg.split('=').last;
      if (v == 'policy' || v == 'opponent' || v == 'all') {
        labelSeats = v;
        continue;
      }
    }
    if (arg.startsWith('--shadow-heuristics=')) {
      // Variants separated by '|': log what each would play on labelled rows.
      shadowVariants = [
        for (final spec in arg.substring(arg.indexOf('=') + 1).split('|'))
          HeuristicOptions.parse(spec),
      ];
      continue;
    }
    if (arg.startsWith('--schupf-rollout-rate=')) {
      final p = double.tryParse(arg.split('=').last);
      if (p != null && p >= 0 && p <= 1) schupfRolloutRate = p;
      continue;
    }
    if (arg.startsWith('--pimc-worlds=')) {
      final p = int.tryParse(arg.split('=').last);
      if (p != null && p >= 0) pimcWorlds = p;
      continue;
    }
    if (arg.startsWith('--schupf-candidates=')) {
      final p = int.tryParse(arg.split('=').last);
      if (p != null && p >= 2) schupfCandidates = p;
      continue;
    }
    if (arg == '--endgame-search') {
      endgameSearch = true;
      continue;
    }
    if (arg == '--endgame-solve') {
      endgameSolve = true;
      continue;
    }
    if (arg == '--opponent-endgame-solve') {
      opponentEndgameSolve = true;
      continue;
    }
    if (arg == '--pimc-solve') {
      pimcSolve = true;
      continue;
    }
    if (arg.startsWith('--belief-net=')) {
      beliefNetPath = arg.substring('--belief-net='.length);
      continue;
    }
    if (arg == '--endgame-belief') {
      endgameBelief = true;
      continue;
    }
    if (arg == '--opponent-endgame-belief') {
      opponentEndgameBelief = true;
      continue;
    }
    if (arg == '--opponent-pimc-solve') {
      opponentPimcSolve = true;
      continue;
    }
    if (arg.startsWith('--pimc-max-cards=')) {
      final k = int.tryParse(arg.split('=').last);
      if (k != null && k >= 3) pimcMaxCards = k;
      continue;
    }
    if (arg.startsWith('--solve-max-cards=')) {
      final k = int.tryParse(arg.split('=').last);
      if (k != null && k >= 2) solveMaxCards = k;
      continue;
    }
    if (arg.startsWith('--solve-budget=')) {
      final k = int.tryParse(arg.split('=').last);
      if (k != null && k >= 1) solveBudget = k;
      continue;
    }
    if (arg == '--opponent-endgame-search') {
      opponentEndgameSearch = true;
      continue;
    }
    if (arg.startsWith('--endgame-worlds=')) {
      final k = int.tryParse(arg.split('=').last);
      if (k != null && k >= 1) endgameWorlds = k;
      continue;
    }
    if (arg.startsWith('--opponent-endgame-max-cards=')) {
      final k = int.tryParse(arg.split('=').last);
      if (k != null && k >= 1) opponentEndgameMaxCards = k;
      continue;
    }
    if (arg.startsWith('--endgame-max-cards=')) {
      final k = int.tryParse(arg.split('=').last);
      if (k != null && k >= 1) endgameMaxCards = k;
      continue;
    }
    if (arg.startsWith('--endgame-margin=')) {
      final m = double.tryParse(arg.split('=').last);
      if (m != null && m >= 0) endgameMargin = m;
      continue;
    }
    if (arg.startsWith('--endgame-max-actions=')) {
      final k = int.tryParse(arg.split('=').last);
      if (k != null && k >= 2) endgameMaxActions = k;
      continue;
    }
    if (arg == '--no-simd') {
      simd = false;
      continue;
    }
    if (arg == '--describe') {
      describe = true;
      continue;
    }
    if (arg == '--counterfactual-calls') {
      counterfactualCalls = true;
      continue;
    }
    if (arg == '--skip-play-rows') {
      skipPlayRows = true;
      continue;
    }
    if (arg == '--shadow-heuristic') {
      shadowHeuristic = true;
      continue;
    }
    if (arg.startsWith('--heuristic=')) {
      heuristic = HeuristicOptions.parse(arg.substring(arg.indexOf('=') + 1));
      continue;
    }
    if (arg.startsWith('--pre-tichu-strength=')) {
      preTichuStrength = double.tryParse(arg.split('=').last);
      continue;
    }
    if (arg.startsWith('--opponent-pre-tichu-strength=')) {
      opponentPreTichuStrength = double.tryParse(arg.split('=').last);
      continue;
    }
    if (arg == '--schupf-extended') {
      schupfExtended = true;
      continue;
    }
    if (arg == '--schupf-label-extended') {
      schupfLabelExtended = true;
      continue;
    }
    if (arg == '--opponent-schupf-extended') {
      opponentSchupfExtended = true;
      continue;
    }
    if (arg.startsWith('--style=')) {
      style = StyleBias.parse(arg.substring(arg.indexOf('=') + 1));
      continue;
    }
    if (arg.startsWith('--opponent-style=')) {
      opponentStyle = StyleBias.parse(arg.substring(arg.indexOf('=') + 1));
      continue;
    }
    if (arg.startsWith('--opponent-heuristic=')) {
      opponentHeuristic = HeuristicOptions.parse(
        arg.substring(arg.indexOf('=') + 1),
      );
      continue;
    }
    if (arg.startsWith('--pre-tichu-net=')) {
      preTichuNetPath = arg.split('=').last;
      continue;
    }
    if (arg.startsWith('--schupf-net=')) {
      schupfNetPath = arg.split('=').last;
      continue;
    }
    if (arg.startsWith('--schupf-epsilon=')) {
      final p = double.tryParse(arg.split('=').last);
      if (p != null && p >= 0 && p <= 1) schupfEpsilon = p;
      continue;
    }
    if (arg.startsWith('--call-epsilon=')) {
      final p = double.tryParse(arg.split('=').last);
      if (p != null && p >= 0 && p <= 1) callEpsilon = p;
      continue;
    }
    if (arg.startsWith('--deal-seed=')) {
      dealSeed = int.tryParse(arg.split('=').last);
      continue;
    }
    stderr.writeln('Unknown argument: $arg');
    exitCode = 64;
    showHelp = true;
  }

  if (!outputProvided &&
      (outputFormat == _HeadlessOutputFormat.bcJsonl ||
          outputFormat == _HeadlessOutputFormat.summary)) {
    outputPath = 'game.jsonl';
  }

  EndgameSearch search({
    required final bool solve,
    required final bool pimc,
    required final bool belief,
    final int? maxCards,
  }) => EndgameSearch(
    beliefWorlds: belief,
    worlds: endgameWorlds,
    maxCards: maxCards ?? endgameMaxCards,
    margin: endgameMargin,
    maxActions: endgameMaxActions,
    solveOneOnOne: solve,
    solveBudget: solveBudget,
    solveMaxCards: solveMaxCards,
    pimcSolve: pimc && solve,
    pimcMaxCards: pimcMaxCards,
  );
  return _HeadlessConfig(
    endgameSearch: endgameSearch
        ? search(solve: endgameSolve, pimc: pimcSolve, belief: endgameBelief)
        : null,
    opponentEndgameSearch: opponentEndgameSearch
        ? search(
            solve: opponentEndgameSolve,
            pimc: opponentPimcSolve,
            belief: opponentEndgameBelief,
            maxCards: opponentEndgameMaxCards,
          )
        : null,
    seed: seed,
    targetScore: targetScore,
    rounds: rounds,
    episodes: episodes,
    maxStepsPerEpisode: maxStepsPerEpisode,
    outputPath: outputPath,
    outputFormat: outputFormat,
    showHelp: showHelp,
    includeTimestamps: includeTimestamps,
    nnPolicyPath: nnPolicyPath,
    opponentPolicyPath: opponentPolicyPath,
    opponentSchupfNetPath: opponentSchupfNetPath,
    opponentTichuNetPath: opponentTichuNetPath,
    epsilon: epsilon,
    mixed: mixed,
    swapTeams: swapTeams,
    episodeOffset: episodeOffset,
    dealSeed: dealSeed,
    tichuNetPath: tichuNetPath,
    grandNetPath: grandNetPath,
    callEpsilon: callEpsilon,
    schupfNetPath: schupfNetPath,
    preTichuNetPath: preTichuNetPath,
    heuristic: heuristic,
    opponentHeuristic: opponentHeuristic,
    style: style,
    opponentStyle: opponentStyle,
    preTichuStrength: preTichuStrength,
    opponentPreTichuStrength: opponentPreTichuStrength,
    schupfExtended: schupfExtended,
    opponentSchupfExtended: opponentSchupfExtended,
    schupfLabelExtended: schupfLabelExtended,
    beliefNetPath: beliefNetPath,
    schupfEpsilon: schupfEpsilon,
    shadowHeuristic: shadowHeuristic,
    skipPlayRows: skipPlayRows,
    counterfactualCalls: counterfactualCalls,
    counterfactualRate: counterfactualRate,
    rolloutRate: rolloutRate,
    rolloutMaxActions: rolloutMaxActions,
    rolloutWorlds: rolloutWorlds,
    leadRolloutRate: leadRolloutRate,
    leadWorlds: leadWorlds,
    sideRolloutRate: sideRolloutRate,
    worldsMinCards: worldsMinCards,
    labelMaxCards: labelMaxCards,
    labelSeats: labelSeats,
    describe: describe,
    shadowVariants: shadowVariants,
    simd: simd,
    schupfRolloutRate: schupfRolloutRate,
    schupfCandidates: schupfCandidates,
    pimcWorlds: pimcWorlds,
  );
}

void _printUsage() {
  stdout.writeln('Headless Tichu automated-opponent runner');
  stdout.writeln('Usage: dart run lib/headless/headless.dart [--seed=N]');
  stdout.writeln('       [--target-score=N] [--rounds=N] [--episodes=N]');
  stdout.writeln('       [--max-steps=N]');
  stdout.writeln('       [--format=csv|bc-jsonl|summary|none] [--output=path]');
  stdout.writeln('       [--no-timestamps]');
  stdout.writeln('       [--nn-policy=model.safetensors] [--mixed]');
  stdout.writeln('       [--opponent-policy=model.safetensors] [--swap-teams]');
  stdout.writeln('       [--opponent-schupf-net=..] [--opponent-tichu-net=..]');
  stdout.writeln('       [--episode-offset=N] [--deal-seed=N]');
  stdout.writeln('       [--tichu-net=..] [--grand-net=..] [--call-epsilon=p]');
  stdout.writeln('       [--schupf-net=..] [--schupf-epsilon=p]');
  stdout.writeln('       [--pre-tichu-net=..]  (Tichu before the schupf)');
  stdout.writeln('       [--heuristic=latest,weight:value,...]');
  stdout.writeln('       [--opponent-heuristic=...]  (TurnScorer weights)');
  stdout.writeln(
    '       [--style=pass:P,spend:S,min-hand:N] [--opponent-style=...]',
  );
  stdout.writeln('       [--shadow-heuristic] [--skip-play-rows]');
  stdout.writeln('       [--counterfactual-calls] [--counterfactual-rate=p]');
  stdout.writeln('       [--rollout-rate=p] [--rollout-max-actions=N]');
  stdout.writeln('       [--rollout-worlds=K] [--worlds-min-cards=N]');
  stdout.writeln('       [--label-max-cards=N]  (label only small hands)');
  stdout.writeln(
    '       [--endgame-solve] [--opponent-endgame-solve] [--solve-budget=N]  '
    '(exact one-on-one endgames, with --endgame-search)',
  );
  stdout.writeln(
    '       [--pre-tichu-strength=X] [--opponent-pre-tichu-strength=X]  '
    '(Tichu before the schupf at 14-card strength >= X)',
  );
  stdout.writeln(
    '       [--schupf-extended] [--opponent-schupf-extended]  '
    '(schupf candidates: partner may get a weak card)',
  );
  stdout.writeln(
    '       [--schupf-label-extended]  (only the schupf labels use them)',
  );
  stdout.writeln(
    '       [--belief-net=..] [--endgame-belief] [--opponent-endgame-belief]  '
    '(search worlds from the card-location model)',
  );
  stdout.writeln(
    '       [--lead-rollout-rate=p] [--lead-worlds=K]  (leads: own rate / worlds)',
  );
  stdout.writeln('       [--side-rollout-rate=p]  (Dragon gift / wish labels)');
  stdout.writeln('       [--label-seats=policy|opponent|all] [--describe]');
  stdout.writeln('       [--shadow-heuristics=spec|spec|...] [--no-simd]');
  stdout.writeln('       [--schupf-rollout-rate=p] [--schupf-candidates=N]');
  stdout.writeln('       [--endgame-search] [--opponent-endgame-search]');
  stdout.writeln('       [--endgame-worlds=8] [--endgame-max-cards=5]');
  stdout.writeln('       [--endgame-margin=10] [--endgame-max-actions=7]');
  stdout.writeln('       [--epsilon=0.1]');
}
