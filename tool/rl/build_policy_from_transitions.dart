import 'dart:convert';
import 'dart:io';

const _policySchemaVersion = 'tichu_rl_policy_v1';
const _expectedTransitionSchemaVersion = 'tichu_rl_transition_v2';

Future<void> main(final List<String> args) async {
  final config = _parseArgs(args);
  if (config.showHelp) {
    _printUsage();
    return;
  }

  final builder = _MonteCarloPolicyBuilder(
    gamma: config.gamma,
    minSamples: config.minSamples,
    expectedTransitionSchemaVersion: _expectedTransitionSchemaVersion,
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
  var gamma = 1.0;
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
  final String schemaVersion;
  final String stateKey;
  final String? stateKeyCoarse;
  final String actionKey;
  final String? actionShapeKey;
  final double reward;
  final double discount;

  const _Transition({
    required this.episode,
    required this.seq,
    required this.schemaVersion,
    required this.stateKey,
    required this.stateKeyCoarse,
    required this.actionKey,
    required this.actionShapeKey,
    required this.reward,
    required this.discount,
  });

  factory _Transition.fromJson(final Map<String, Object?> json) {
    final episode = json['episode'];
    final schemaVersion = json['schema_version'];
    final stateKey = json['state_key'];
    final stateKeyCoarse = json['state_key_coarse'];
    final actionKey = json['action_key'];
    final actionShapeKey = json['action_shape_key'];
    final reward = json['reward'];
    final discount = json['discount'];
    final done = json['done'];

    if (episode is! num ||
        schemaVersion is! String ||
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
      schemaVersion: schemaVersion,
      stateKey: stateKey,
      stateKeyCoarse: stateKeyCoarse is String ? stateKeyCoarse : null,
      actionKey: actionKey,
      actionShapeKey: actionShapeKey is String ? actionShapeKey : null,
      reward: reward.toDouble(),
      discount: normalizedDiscount,
    );
  }
}

class _StateActionAccumulator {
  double sumReturns = 0;
  int samples = 0;

  void add(final double value) {
    sumReturns += value;
    samples++;
  }

  double get mean => samples == 0 ? 0 : sumReturns / samples;
}

class _MonteCarloPolicyBuilder {
  final double gamma;
  final int minSamples;
  final String expectedTransitionSchemaVersion;

  int episodesSeen = 0;
  int transitionsUsed = 0;

  final Map<String, Map<String, _StateActionAccumulator>> _accumulators = {};
  final Map<String, Map<String, _StateActionAccumulator>> _coarseAccumulators =
      {};

  _MonteCarloPolicyBuilder({
    required this.gamma,
    required this.minSamples,
    required this.expectedTransitionSchemaVersion,
  });

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

      if (transition.schemaVersion != expectedTransitionSchemaVersion) {
        throw FormatException(
          'Line $lineNumber schema_version ${transition.schemaVersion} does not match expected $expectedTransitionSchemaVersion.',
        );
      }

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
    final (stateActionValues, entries) = _buildActionTable(_accumulators);
    final (coarseStateActionValues, coarseEntries) = _buildActionTable(
      _coarseAccumulators,
    );

    return {
      'schema_version': _policySchemaVersion,
      'source_transition_schema': expectedTransitionSchemaVersion,
      'builder': {
        'algorithm': 'monte_carlo_state_action_returns',
        'gamma': gamma,
        'min_samples': minSamples,
        'uses_action_shape_backoff': true,
        'uses_coarse_state_keys': true,
        'episodes_seen': episodesSeen,
        'transitions_used': transitionsUsed,
        'generated_at_utc': DateTime.now().toUtc().toIso8601String(),
      },
      'state_action_values': stateActionValues,
      'coarse_state_action_values': coarseStateActionValues,
      'entries': entries,
      'coarse_entries': coarseEntries,
    };
  }

  void _processEpisode(final List<_Transition> episodeTransitions) {
    if (episodeTransitions.isEmpty) {
      return;
    }

    episodesSeen++;

    var g = 0.0;
    for (final transition in episodeTransitions.reversed) {
      g = transition.reward + gamma * transition.discount * g;
      transitionsUsed++;

      _accumulate(_accumulators, transition.stateKey, transition.actionKey, g);
      if (transition.actionShapeKey != null &&
          transition.actionShapeKey != transition.actionKey) {
        _accumulate(
          _accumulators,
          transition.stateKey,
          transition.actionShapeKey!,
          g,
        );
      }

      final coarseStateKey = transition.stateKeyCoarse;
      if (coarseStateKey != null && coarseStateKey.isNotEmpty) {
        _accumulate(
          _coarseAccumulators,
          coarseStateKey,
          transition.actionKey,
          g,
        );
        if (transition.actionShapeKey != null &&
            transition.actionShapeKey != transition.actionKey) {
          _accumulate(
            _coarseAccumulators,
            coarseStateKey,
            transition.actionShapeKey!,
            g,
          );
        }
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

  (Map<String, Object?>, List<Map<String, Object?>>) _buildActionTable(
    final Map<String, Map<String, _StateActionAccumulator>> source,
  ) {
    final stateActionValues = <String, Object?>{};
    final entries = <Map<String, Object?>>[];

    final sortedStates = source.keys.toList()..sort();
    for (final stateKey in sortedStates) {
      final actionAcc = source[stateKey]!;
      final sortedActions = actionAcc.keys.toList()..sort();

      final actionValues = <String, Object?>{};
      for (final actionKey in sortedActions) {
        final acc = actionAcc[actionKey]!;
        if (acc.samples < minSamples) {
          continue;
        }

        final mean = acc.mean;
        actionValues[actionKey] = mean;
        entries.add({
          'state_key': stateKey,
          'action_key': actionKey,
          'value': mean,
          'samples': acc.samples,
        });
      }

      if (actionValues.isNotEmpty) {
        stateActionValues[stateKey] = actionValues;
      }
    }

    return (stateActionValues, entries);
  }
}
