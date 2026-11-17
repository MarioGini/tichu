import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:tichu/agents/bot_config.dart';
import 'package:tichu/agents/heuristic_options.dart';
import 'package:tichu/agents/legal_play_guard.dart';
import 'package:tichu/agents/nn/feature_encoder.dart';
import 'package:tichu/agents/nn/nn_schupf_strategy.dart';
import 'package:tichu/agents/nn/nn_tichu_call_strategy.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/agents/table_relationships.dart';
import 'package:tichu/agents/tichu_call_strategy.dart';
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

part 'bc_action_encoding.dart';
part 'bc_transition_writer.dart';
part 'headless_args.dart';
part 'csv_event_writer.dart';
part 'headless_decisions.dart';
part 'headless_exploration.dart';
part 'headless_legality.dart';
part 'headless_rollouts.dart';
part 'headless_schupf_labels.dart';
part 'headless_simulator.dart';
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
    simdInference: config.simd,
  );
  final opponentPolicy = await _loadNet(config.opponentPolicyPath);
  final policyFactory = policyConfig.build;
  final opponentFactory = BotConfig(
    play: opponentPolicy,
    heuristicOptions: config.opponentHeuristic,
    simdInference: config.simd,
  ).build;

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
    counterfactualRate: config.counterfactualRate,
    rolloutRate: config.rolloutRate,
    rolloutMaxActions: config.rolloutMaxActions,
    // Which seats get rollout labels: by default the policy team when it
    // plays a different opponent (--mixed / --opponent-policy), else all.
    isLearnerSeat:
        (opponentPolicy != null || config.mixed) && config.labelSeats != 'all'
        ? (final seat) =>
              (seat.isEven != config.swapTeams) ==
              (config.labelSeats == 'policy')
        : (final _) => true,
    describe: config.describe,
    shadowVariants: config.shadowVariants,
    schupfRolloutRate: config.schupfRolloutRate,
    schupfCandidates: config.schupfCandidates,
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
