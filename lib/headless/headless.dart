import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:tichu/agents/bot_config.dart';
import 'package:tichu/agents/heuristic_options.dart';
import 'package:tichu/agents/legal_play_guard.dart';
import 'package:tichu/agents/mcts/ismcts_play_selection_strategy.dart';
import 'package:tichu/agents/nn/feature_encoder.dart';
import 'package:tichu/agents/nn/nn_schupf_strategy.dart';
import 'package:tichu/agents/nn/nn_tichu_call_strategy.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/agents/table_relationships.dart';
import 'package:tichu/game/agent_decisions.dart';
import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';
import 'package:tichu/game/turn/find_turn.dart';
import 'package:tichu/game/turn/move_generator.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/turn_handler.dart';
import 'package:tichu/game/turn/wish_logic.dart';

part 'headless_simulator.dart';
part 'csv_event_writer.dart';
part 'bc_transition_writer.dart';
part 'summary_writer.dart';

const _defaultTargetScore = 1000;
const _defaultEpisodes = 1;
const _defaultMaxStepsPerEpisode = 200000;

Future<void> main(final List<String> args) async {
  final config = _parseArgs(args);
  if (config.showHelp) {
    _printUsage();
    return;
  }

  final outputSink = config.outputFormat == _HeadlessOutputFormat.none
      ? null
      : File(config.outputPath).openWrite();

  final random = config.seed == null ? Random() : Random(config.seed);

  // The policy team uses every learned component given on the command line;
  // the opponent team uses --opponent-policy for play (or the heuristic) and
  // heuristic calls / schupf.
  final policyConfig = BotConfig(
    play: await _loadNet(config.nnPolicyPath),
    tichu: await _loadNet(config.tichuNetPath),
    grandTichu: await _loadNet(config.grandNetPath),
    preSchupfTichu: await _loadNet(config.preTichuNetPath),
    schupf: await _loadNet(config.schupfNetPath),
    heuristicOptions: config.heuristic,
  );
  final opponentPolicy = await _loadNet(config.opponentPolicyPath);
  final policyFactory = _buildAgentFactory(
    config: policyConfig,
    useIsmcts: config.useIsmcts,
    ismctsSimulations: config.ismctsSimulations,
    valueNet: await _loadNet(config.valueNetPath),
    random: random,
  );
  final opponentFactory = _buildAgentFactory(
    config: BotConfig(
      play: opponentPolicy,
      heuristicOptions: config.opponentHeuristic,
    ),
    random: random,
  );

  final PlayerAgent Function(String, int) agentFactory;
  if (opponentPolicy != null || config.mixed) {
    // Self-play / mixed mode: team0 (even seats) plays the loaded policy,
    // team1 (odd seats) plays the frozen opponent policy (or the heuristic).
    // --swap-teams flips this so duplicate evaluation can replay the same
    // deals with the policy on the other seats.
    agentFactory = (final playerId, final seat) =>
        seat.isEven != config.swapTeams
        ? policyFactory(playerId)
        : opponentFactory(playerId);
  } else {
    agentFactory = (final playerId, final _) => policyFactory(playerId);
  }

  final simulator = _HeadlessSimulator(
    random: random,
    targetScore: config.targetScore,
    roundsLimit: config.rounds,
    episodes: config.episodes,
    maxStepsPerEpisode: config.maxStepsPerEpisode,
    outputFormat: config.outputFormat,
    output: outputSink,
    includeTimestamps: config.includeTimestamps,
    epsilon: config.epsilon,
    agentFactory: agentFactory,
    episodeOffset: config.episodeOffset,
    dealSeed: config.dealSeed,
    callEpsilon: config.callEpsilon,
    schupfEpsilon: config.schupfEpsilon,
    shadowHeuristic: config.shadowHeuristic,
    skipPlayRows: config.skipPlayRows,
    counterfactualCalls: config.counterfactualCalls,
  );

  try {
    await simulator.run();
  } finally {
    if (outputSink != null) {
      await outputSink.flush();
      await outputSink.close();
    }
  }
}

// ── Config & CLI ──────────────────────────────────────────────────────────

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
  final double epsilon;
  final bool useIsmcts;
  final int ismctsSimulations;
  final bool mixed;
  final bool swapTeams;
  final int episodeOffset;
  final int? dealSeed;
  final String? valueNetPath;
  final String? tichuNetPath;
  final String? grandNetPath;
  final double callEpsilon;
  final String? schupfNetPath;
  final String? preTichuNetPath;
  final HeuristicOptions heuristic;
  final HeuristicOptions opponentHeuristic;
  final double schupfEpsilon;
  final bool shadowHeuristic;
  final bool skipPlayRows;
  final bool counterfactualCalls;

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
    required this.epsilon,
    required this.useIsmcts,
    required this.ismctsSimulations,
    required this.mixed,
    required this.swapTeams,
    required this.episodeOffset,
    required this.dealSeed,
    required this.valueNetPath,
    required this.tichuNetPath,
    required this.grandNetPath,
    required this.callEpsilon,
    required this.schupfNetPath,
    required this.preTichuNetPath,
    required this.heuristic,
    required this.opponentHeuristic,
    required this.schupfEpsilon,
    required this.shadowHeuristic,
    required this.skipPlayRows,
    required this.counterfactualCalls,
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
  var outputProvided = false;
  var showHelp = false;
  var epsilon = 0.0;
  var useIsmcts = false;
  var ismctsSimulations = 100;
  var mixed = false;
  var swapTeams = false;
  var episodeOffset = 0;
  int? dealSeed;
  String? valueNetPath;
  String? tichuNetPath;
  String? grandNetPath;
  var callEpsilon = 0.0;
  String? schupfNetPath;
  String? preTichuNetPath;
  var heuristic = HeuristicOptions.latest;
  var opponentHeuristic = HeuristicOptions.latest;
  var schupfEpsilon = 0.0;
  var shadowHeuristic = false;
  var skipPlayRows = false;
  var counterfactualCalls = false;

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
    if (arg.startsWith('--opponent-policy=')) {
      opponentPolicyPath = arg.split('=').last;
      continue;
    }
    if (arg == '--ismcts') {
      useIsmcts = true;
      continue;
    }
    if (arg.startsWith('--ismcts-simulations=')) {
      final p = int.tryParse(arg.split('=').last);
      if (p != null && p > 0) ismctsSimulations = p;
      useIsmcts = true;
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
      heuristic = HeuristicOptions.parse(arg.split('=').last);
      continue;
    }
    if (arg.startsWith('--opponent-heuristic=')) {
      opponentHeuristic = HeuristicOptions.parse(arg.split('=').last);
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
    if (arg.startsWith('--value-net=')) {
      valueNetPath = arg.split('=').last;
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

  return _HeadlessConfig(
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
    epsilon: epsilon,
    useIsmcts: useIsmcts,
    ismctsSimulations: ismctsSimulations,
    mixed: mixed,
    swapTeams: swapTeams,
    episodeOffset: episodeOffset,
    dealSeed: dealSeed,
    valueNetPath: valueNetPath,
    tichuNetPath: tichuNetPath,
    grandNetPath: grandNetPath,
    callEpsilon: callEpsilon,
    schupfNetPath: schupfNetPath,
    preTichuNetPath: preTichuNetPath,
    heuristic: heuristic,
    opponentHeuristic: opponentHeuristic,
    schupfEpsilon: schupfEpsilon,
    shadowHeuristic: shadowHeuristic,
    skipPlayRows: skipPlayRows,
    counterfactualCalls: counterfactualCalls,
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
  stdout.writeln('       [--episode-offset=N] [--deal-seed=N]');
  stdout.writeln('       [--ismcts] [--ismcts-simulations=N]');
  stdout.writeln('       [--value-net=value.safetensors]');
  stdout.writeln('       [--tichu-net=..] [--grand-net=..] [--call-epsilon=p]');
  stdout.writeln('       [--schupf-net=..] [--schupf-epsilon=p]');
  stdout.writeln('       [--pre-tichu-net=..]  (Tichu before the schupf)');
  stdout.writeln('       [--heuristic=latest|legacy|support,announce,strict]');
  stdout.writeln('       [--opponent-heuristic=...]  (A/B heuristic rules)');
  stdout.writeln('       [--shadow-heuristic] [--skip-play-rows]');
  stdout.writeln('       [--counterfactual-calls]');
  stdout.writeln('       [--epsilon=0.1]');
}

// ── Players & Agent Factory ───────────────────────────────────────────────

List<GamePlayer> _buildAutomatedPlayers() => const [
  GamePlayer(id: 'auto_1', name: 'P1', seat: 0, type: PlayerType.automated),
  GamePlayer(id: 'auto_2', name: 'P2', seat: 1, type: PlayerType.automated),
  GamePlayer(id: 'auto_3', name: 'P3', seat: 2, type: PlayerType.automated),
  GamePlayer(id: 'auto_4', name: 'P4', seat: 3, type: PlayerType.automated),
];

String _cardToken(final Card card) {
  if (card.face == CardFace.phoenix) {
    return 'phoenix:${card.value.toStringAsFixed(1)}';
  }
  return '${card.face.name}-${card.color.name}';
}

Future<LoadedNet?> _loadNet(final String? path) async {
  if (path == null || path.isEmpty) return null;
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('Network file does not exist: $path');
  }
  return LoadedNet.fromBytes(await file.readAsBytes());
}

/// Agent factory for one team: a [BotConfig] (learned components or the
/// heuristic), optionally with a search player for the play phase.
PlayerAgent Function(String playerId) _buildAgentFactory({
  required final BotConfig config,
  final bool useIsmcts = false,
  final int ismctsSimulations = 100,
  final LoadedNet? valueNet,
  final Random? random,
}) {
  if (useIsmcts) {
    return (final playerId) => config.build(
      playerId,
      playOverride: IsmctsPlaySelectionStrategy(
        playerId: playerId,
        numSimulations: ismctsSimulations,
        valueNetwork: valueNet?.network,
        valueNetworkMean: valueNet?.targetMean,
        valueNetworkStd: valueNet?.targetStd,
        random: random,
      ),
    );
  }
  return config.build;
}
