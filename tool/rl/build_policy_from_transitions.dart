import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

Future<void> main(final List<String> args) async {
  final config = _parseArgs(args);
  if (config.showHelp) {
    _printUsage();
    return;
  }

  final builder = _MonteCarloPolicyBuilder(
    gamma: config.gamma,
    minSamples: config.minSamples,
  );

  await builder.ingestJsonl(File(config.inputPath));
  final policy = builder.buildPolicy();

  final outputFile = File(config.outputPath);
  await outputFile.create(recursive: true);
  await outputFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(policy),
  );

  stdout.writeln(
    'policy_written,${outputFile.path},episodes=${builder.episodesSeen},transitions=${builder.transitionsUsed}',
  );
}

class _Config {
  final String inputPath;
  final String outputPath;
  final double gamma;
  final int minSamples;
  final bool showHelp;

  const _Config({
    required this.inputPath,
    required this.outputPath,
    required this.gamma,
    required this.minSamples,
    required this.showHelp,
  });
}

_Config _parseArgs(final List<String> args) {
  var inputPath = '';
  var outputPath = '';
  var gamma = 0.99;
  var minSamples = 1;
  var showHelp = false;

  for (final arg in args) {
    if (arg == '--help' || arg == '-h') {
      showHelp = true;
      continue;
    }
    if (arg.startsWith('--input=')) {
      inputPath = arg.split('=').last;
      continue;
    }
    if (arg.startsWith('--output=')) {
      outputPath = arg.split('=').last;
      continue;
    }
    if (arg.startsWith('--gamma=')) {
      final parsed = double.tryParse(arg.split('=').last);
      if (parsed != null) {
        gamma = parsed;
      }
      continue;
    }
    if (arg.startsWith('--min-samples=')) {
      final parsed = int.tryParse(arg.split('=').last);
      if (parsed != null && parsed > 0) {
        minSamples = parsed;
      }
      continue;
    }
  }

  if (!showHelp && (inputPath.isEmpty || outputPath.isEmpty)) {
    throw ArgumentError(
      'Missing required arguments. Use --input=... and --output=... (or --help).',
    );
  }

  if (gamma < 0 || gamma > 1) {
    throw ArgumentError('--gamma must be between 0 and 1.');
  }

  return _Config(
    inputPath: inputPath,
    outputPath: outputPath,
    gamma: gamma,
    minSamples: minSamples,
    showHelp: showHelp,
  );
}

void _printUsage() {
  stdout.writeln('Build a policy table from headless RL transition JSONL.');
  stdout.writeln('Usage: dart run tool/rl/build_policy_from_transitions.dart');
  stdout.writeln('       --input=trajectories.jsonl --output=policy.json');
  stdout.writeln('       [--gamma=1.0] [--min-samples=1]');
}

class _Transition {
  final int episode;
  final int? seq;
  final int team;
  final String stateKey;
  final String? stateKeyCoarse;
  final String actionKey;
  final String? actionShapeKey;
  final String? policyActionKey;
  final String? actionType;
  final double reward;
  final double discount;

  const _Transition({
    required this.episode,
    required this.seq,
    required this.team,
    required this.stateKey,
    required this.stateKeyCoarse,
    required this.actionKey,
    required this.actionShapeKey,
    required this.policyActionKey,
    required this.actionType,
    required this.reward,
    required this.discount,
  });

  factory _Transition.fromJson(final Map<String, Object?> json) {
    final episode = json['episode'];
    final stateKey = json['state_key'];
    final stateKeyCoarse = json['state_key_coarse'];
    final actionKey = json['action_key'];
    final actionShapeKey = json['action_shape_key'];
    final policyActionKey = json['policy_action_key'];
    final actionType = json['action_type'];
    final reward = json['learning_reward'] ?? json['reward'];
    final discount = json['discount'];
    final done = json['done'];
    final team = json['team'];

    if (episode is! num ||
        stateKey is! String ||
        actionKey is! String ||
        reward is! num) {
      throw const FormatException('Missing required transition fields.');
    }

    final normalizedDiscount = switch (discount) {
      final num value => value.toDouble(),
      _ when done is bool => done ? 0.0 : 1.0,
      _ => 1.0,
    };

    final seq = json['seq'];

    return _Transition(
      episode: episode.toInt(),
      seq: seq is num ? seq.toInt() : null,
      team: team is num ? team.toInt() : 0,
      stateKey: stateKey,
      stateKeyCoarse: stateKeyCoarse is String ? stateKeyCoarse : null,
      actionKey: actionKey,
      actionShapeKey: actionShapeKey is String ? actionShapeKey : null,
      policyActionKey: policyActionKey is String ? policyActionKey : null,
      actionType: actionType is String ? actionType : null,
      reward: reward.toDouble(),
      discount: normalizedDiscount,
    );
  }
}

class _StateActionAccumulator {
  double sumReturns = 0;
  double sumSquaredReturns = 0;
  int samples = 0;

  void add(final double value) {
    sumReturns += value;
    sumSquaredReturns += value * value;
    samples++;
  }

  double get mean => samples == 0 ? 0 : sumReturns / samples;

  double get standardError {
    if (samples < 2) return 0;
    final variance =
        ((sumSquaredReturns - (sumReturns * sumReturns / samples)) /
                (samples - 1))
            .clamp(0, double.infinity);
    return math.sqrt(variance / samples);
  }
}

class _MonteCarloPolicyBuilder {
  final double gamma;
  final int minSamples;

  int episodesSeen = 0;
  int transitionsSeen = 0;
  int transitionsUsed = 0;

  final Map<String, Map<String, _StateActionAccumulator>> _accumulators = {};
  final Map<String, Map<String, _StateActionAccumulator>> _coarseAccumulators =
      {};

  _MonteCarloPolicyBuilder({required this.gamma, required this.minSamples});

  Future<void> ingestJsonl(final File inputFile) async {
    if (!inputFile.existsSync()) {
      throw StateError('Input file does not exist: ${inputFile.path}');
    }

    final episodeBuffer = <_Transition>[];
    int? currentEpisode;
    int? lastSeqInEpisode;
    var lineNumber = 0;

    final lines = inputFile
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final rawLine in lines) {
      lineNumber++;
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }

      final decoded = jsonDecode(line);
      if (decoded is! Map<String, Object?>) {
        throw FormatException('Line $lineNumber is not a JSON object.');
      }

      final transition = _Transition.fromJson(decoded);

      currentEpisode ??= transition.episode;

      if (transition.episode < currentEpisode) {
        throw FormatException(
          'Input must be grouped by episode in ascending order. Found episode ${transition.episode} after $currentEpisode at line $lineNumber.',
        );
      }

      if (transition.episode > currentEpisode) {
        _processEpisode(episodeBuffer);
        episodeBuffer.clear();
        currentEpisode = transition.episode;
        lastSeqInEpisode = null;
      }

      if (transition.seq != null &&
          lastSeqInEpisode != null &&
          transition.seq! < lastSeqInEpisode) {
        throw FormatException(
          'Episode ${transition.episode} seq is not ascending at line $lineNumber.',
        );
      }
      lastSeqInEpisode = transition.seq ?? lastSeqInEpisode;

      episodeBuffer.add(transition);
    }

    if (episodeBuffer.isNotEmpty) {
      _processEpisode(episodeBuffer);
    }
  }

  Map<String, Object?> buildPolicy() {
    final stateActionValues = _buildActionTable(_accumulators);
    final coarseStateActionValues = _buildActionTable(_coarseAccumulators);

    return {
      'builder': {
        'algorithm': 'monte_carlo_conservative_advantage',
        'gamma': gamma,
        'min_samples': minSamples,
        'episodes_seen': episodesSeen,
        'transitions_seen': transitionsSeen,
        'transitions_used': transitionsUsed,
        'generated_at_utc': DateTime.now().toUtc().toIso8601String(),
      },
      'state_action_values': stateActionValues,
      'coarse_state_action_values': coarseStateActionValues,
    };
  }

  void _processEpisode(final List<_Transition> episodeTransitions) {
    if (episodeTransitions.isEmpty) {
      return;
    }

    episodesSeen++;
    transitionsSeen += episodeTransitions.length;

    // Build a zero-sum return for each team over the complete timeline. An
    // opponent's progress or score is negative reward rather than an event
    // that disappears from the return entirely.
    for (final team in const [0, 1]) {
      var g = 0.0;
      for (final transition in episodeTransitions.reversed) {
        final teamReward = transition.team == team
            ? transition.reward
            : -transition.reward;
        g = teamReward + gamma * transition.discount * g;

        if (transition.team != team || transition.actionType != 'play') {
          continue;
        }

        final policyActionKey =
            transition.policyActionKey ?? transition.actionShapeKey;
        final coarseStateKey = transition.stateKeyCoarse;
        if (policyActionKey == null ||
            policyActionKey.isEmpty ||
            coarseStateKey == null ||
            coarseStateKey.isEmpty) {
          continue;
        }

        transitionsUsed++;
        _accumulate(_coarseAccumulators, coarseStateKey, policyActionKey, g);
      }
    }
  }

  void _accumulate(
    final Map<String, Map<String, _StateActionAccumulator>> table,
    final String stateKey,
    final String actionKey,
    final double value,
  ) {
    final byAction = table.putIfAbsent(
      stateKey,
      () => <String, _StateActionAccumulator>{},
    );
    final acc = byAction.putIfAbsent(actionKey, _StateActionAccumulator.new);
    acc.add(value);
  }

  Map<String, Object?> _buildActionTable(
    final Map<String, Map<String, _StateActionAccumulator>> source,
  ) {
    final stateActionValues = <String, Object?>{};

    final sortedStates = source.keys.toList()..sort();
    for (final stateKey in sortedStates) {
      final actionAcc = source[stateKey]!;
      final eligible = actionAcc.entries
          .where((final entry) => entry.value.samples >= minSamples)
          .toList();
      if (eligible.length < 2) {
        continue;
      }

      final totalSamples = eligible.fold<int>(
        0,
        (final total, final entry) => total + entry.value.samples,
      );
      final stateMean =
          eligible.fold<double>(
            0,
            (final total, final entry) => total + entry.value.sumReturns,
          ) /
          totalSamples;
      eligible.sort((final a, final b) => a.key.compareTo(b.key));

      final actionValues = <String, Object?>{};
      for (final entry in eligible) {
        final advantage = entry.value.mean - stateMean;
        final conservativeAdvantage =
            advantage - 1.96 * entry.value.standardError;
        if (conservativeAdvantage > 0) {
          actionValues[entry.key] = conservativeAdvantage;
        }
      }

      if (actionValues.isNotEmpty) {
        stateActionValues[stateKey] = actionValues;
      }
    }

    return stateActionValues;
  }
}
