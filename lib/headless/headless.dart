import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:tichu/agents/hand_evaluator.dart';
import 'package:tichu/agents/mcts/ismcts_play_selection_strategy.dart';
import 'package:tichu/agents/mcts/mcts_play_selection_strategy.dart';
import 'package:tichu/agents/nn/mlp.dart';
import 'package:tichu/agents/nn/nn_play_selection_strategy.dart';
import 'package:tichu/agents/rl_codec.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/scoring/score_data.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';
import 'package:tichu/game/turn/find_turn.dart';
import 'package:tichu/game/turn/move_generator.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/turn_handler.dart';
import 'package:tichu/game/turn/wish_logic.dart';

part 'headless_simulator.dart';
part 'csv_event_writer.dart';
part 'rl_transition_writer.dart';

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

  final nnPolicy = await _loadNnPolicy(config.nnPolicyPath);
  final policyFactory = _buildAgentFactory(
    nnPolicy: nnPolicy,
    useMcts: config.useMcts,
    useIsmcts: config.useIsmcts,
    mctsDeterminizations: config.mctsDeterminizations,
    ismctsSimulations: config.ismctsSimulations,
    random: random,
  );
  final heuristicFactory = _buildAgentFactory(
    nnPolicy: null,
    random: random,
  );

  final PlayerAgent Function(String, int) agentFactory;
  if (config.mixed) {
    agentFactory = (final playerId, final seat) =>
        seat.isEven ? policyFactory(playerId) : heuristicFactory(playerId);
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
    includeLegalTurnCount: config.includeLegalTurnCount,
    epsilon: config.epsilon,
    agentFactory: agentFactory,
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
  final bool includeLegalTurnCount;
  final String? nnPolicyPath;
  final double epsilon;
  final bool useMcts;
  final int mctsDeterminizations;
  final bool useIsmcts;
  final int ismctsSimulations;
  final bool mixed;

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
    required this.includeLegalTurnCount,
    required this.nnPolicyPath,
    required this.epsilon,
    required this.useMcts,
    required this.mctsDeterminizations,
    required this.useIsmcts,
    required this.ismctsSimulations,
    required this.mixed,
  });
}

enum _HeadlessOutputFormat { csv, rlJsonl, none }

_HeadlessConfig _parseArgs(final List<String> args) {
  int? seed;
  var targetScore = _defaultTargetScore;
  int? rounds;
  var outputPath = 'game.csv';
  var outputFormat = _HeadlessOutputFormat.csv;
  var episodes = _defaultEpisodes;
  var maxStepsPerEpisode = _defaultMaxStepsPerEpisode;
  var includeTimestamps = true;
  var includeLegalTurnCount = false;
  String? nnPolicyPath;
  var outputProvided = false;
  var showHelp = false;
  var epsilon = 0.0;
  var useMcts = false;
  var mctsDeterminizations = 20;
  var useIsmcts = false;
  var ismctsSimulations = 100;
  var mixed = false;

  for (final arg in args) {
    if (arg == '--help' || arg == '-h') { showHelp = true; continue; }
    if (arg.startsWith('--seed=')) { seed = int.tryParse(arg.split('=').last); continue; }
    if (arg.startsWith('--target-score=')) { targetScore = int.tryParse(arg.split('=').last) ?? _defaultTargetScore; continue; }
    if (arg.startsWith('--rounds=')) { final p = int.tryParse(arg.split('=').last); if (p != null && p > 0) rounds = p; continue; }
    if (arg.startsWith('--episodes=')) { final p = int.tryParse(arg.split('=').last); if (p != null && p > 0) episodes = p; continue; }
    if (arg.startsWith('--max-steps=')) { final p = int.tryParse(arg.split('=').last); if (p != null && p > 0) maxStepsPerEpisode = p; continue; }
    if (arg.startsWith('--format=')) {
      switch (arg.split('=').last) {
        case 'csv': outputFormat = _HeadlessOutputFormat.csv;
        case 'rl-jsonl': outputFormat = _HeadlessOutputFormat.rlJsonl;
        case 'none': outputFormat = _HeadlessOutputFormat.none;
      }
      continue;
    }
    if (arg == '--rl') { outputFormat = _HeadlessOutputFormat.rlJsonl; continue; }
    if (arg == '--no-timestamps') { includeTimestamps = false; continue; }
    if (arg == '--rl-legal-count') { includeLegalTurnCount = true; continue; }
    if (arg.startsWith('--output=')) { outputPath = arg.split('=').last; outputProvided = true; continue; }
    if (arg.startsWith('--epsilon=')) { final p = double.tryParse(arg.split('=').last); if (p != null && p >= 0 && p <= 1) epsilon = p; continue; }
    if (arg == '--mcts') { useMcts = true; continue; }
    if (arg.startsWith('--mcts-determinizations=')) { final p = int.tryParse(arg.split('=').last); if (p != null && p > 0) mctsDeterminizations = p; useMcts = true; continue; }
    if (arg.startsWith('--nn-policy=')) { nnPolicyPath = arg.split('=').last; continue; }
    if (arg == '--ismcts') { useIsmcts = true; continue; }
    if (arg.startsWith('--ismcts-simulations=')) { final p = int.tryParse(arg.split('=').last); if (p != null && p > 0) ismctsSimulations = p; useIsmcts = true; continue; }
    if (arg == '--mixed') { mixed = true; continue; }
  }

  if (!outputProvided && outputFormat == _HeadlessOutputFormat.rlJsonl) {
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
    includeLegalTurnCount: includeLegalTurnCount,
    nnPolicyPath: nnPolicyPath,
    epsilon: epsilon,
    useMcts: useMcts,
    mctsDeterminizations: mctsDeterminizations,
    useIsmcts: useIsmcts,
    ismctsSimulations: ismctsSimulations,
    mixed: mixed,
  );
}

void _printUsage() {
  stdout.writeln('Headless Tichu automated-opponent runner');
  stdout.writeln('Usage: dart run lib/headless/headless.dart [--seed=N]');
  stdout.writeln('       [--target-score=N] [--rounds=N] [--episodes=N]');
  stdout.writeln('       [--format=csv|rl-jsonl|none] [--output=path]');
  stdout.writeln('       [--nn-policy=model.safetensors] [--mixed]');
  stdout.writeln('       [--epsilon=0.1] [--mcts] [--ismcts]');
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

class _NnPolicyData {
  final Mlp network;
  final double targetMean;
  final double targetStd;

  const _NnPolicyData({
    required this.network,
    required this.targetMean,
    required this.targetStd,
  });
}

Future<_NnPolicyData?> _loadNnPolicy(final String? path) async {
  if (path == null || path.isEmpty) return null;

  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('NN policy file does not exist: $path');
  }

  final bytes = await file.readAsBytes();
  final (network, mean, std) = Mlp.fromSafetensorsBytes(bytes);
  return _NnPolicyData(network: network, targetMean: mean, targetStd: std);
}

PlayerAgent Function(String playerId) _buildAgentFactory({
  required final _NnPolicyData? nnPolicy,
  final bool useMcts = false,
  final bool useIsmcts = false,
  final int mctsDeterminizations = 20,
  final int ismctsSimulations = 100,
  final Random? random,
}) {
  if (useIsmcts) {
    return (final playerId) => SmartAiAgent(
      playerId,
      playSelectionStrategy: IsmctsPlaySelectionStrategy(
        playerId: playerId,
        numSimulations: ismctsSimulations,
        valueNetwork: nnPolicy?.network,
        valueNetworkMean: nnPolicy?.targetMean,
        valueNetworkStd: nnPolicy?.targetStd,
        random: random,
      ),
    );
  }

  if (useMcts) {
    return (final playerId) => SmartAiAgent(
      playerId,
      playSelectionStrategy: MctsPlaySelectionStrategy(
        playerId: playerId,
        numDeterminizations: mctsDeterminizations,
        random: random,
      ),
    );
  }

  if (nnPolicy != null) {
    return (final playerId) => SmartAiAgent(
      playerId,
      playSelectionStrategy: NnPlaySelectionStrategy(
        playerId: playerId,
        network: nnPolicy.network,
      ),
    );
  }

  return SmartAiAgent.new;
}
