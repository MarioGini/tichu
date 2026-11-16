part of 'headless.dart';

class _HeadlessSimulator {
  final Random random;
  final int targetScore;
  final int? roundsLimit;
  final int episodes;
  final int maxStepsPerEpisode;
  final _HeadlessOutputFormat outputFormat;
  final IOSink? output;
  final bool includeTimestamps;
  final double epsilon;
  final PlayerAgent Function(String playerId, int seat) agentFactory;

  /// Added to the local episode index, so shards emit globally unique
  /// episode numbers (episode = episodeOffset + 1 .. episodeOffset + N).
  final int episodeOffset;

  /// When set, deals come from `Random(dealSeed ^ episode-hash)` instead of
  /// the shared [random]. Deals then depend only on (dealSeed, episode), not
  /// on agent decisions, which enables duplicate (team-swapped) evaluation.
  final int? dealSeed;

  /// Probability of replacing a schupf selection with a random perturbation
  /// (exploration for training the schupf net). Schupf rows are always
  /// logged in bc-jsonl output.
  final double schupfEpsilon;

  /// Probability of flipping a Tichu / Grand Tichu decision (exploration
  /// for training call-value nets). Only the first Tichu opportunity per
  /// player and round is explored and logged.
  final double callEpsilon;

  /// Log, for every play/pass decision, what the heuristic would have done
  /// (`shadow_index` in bc-jsonl) — used by `rl/analyze_games.py`.
  final bool shadowHeuristic;

  /// Label each logged Tichu decision with its exact counterfactual value
  /// (round forked and played both ways), see [_counterfactualCall].
  final bool counterfactualCalls;

  /// Share of call decisions that get a counterfactual label (each label
  /// replays the rest of the round twice, so labelling every decision makes
  /// games ~30x slower).
  final double counterfactualRate;

  bool _labelCounterfactual() =>
      counterfactualCalls &&
      _bcWriter != null &&
      (counterfactualRate >= 1 || random.nextDouble() < counterfactualRate);

  /// Omit play/pass rows from bc-jsonl (call / schupf / round data only).
  final bool skipPlayRows;
  final _shadowAgents = <String, SmartAiAgent>{};

  /// Set by [_selectAction] when the returned action came from ε-exploration.
  var _lastActionExplored = false;

  _BcTransitionWriter? _bcWriter;

  /// Hand sizes by seat at the moment the first player went out this round.
  Map<int, int>? _cardsAtFirstOut;
  final _preSchupfDecided = <String>{};
  var _preSchupfRound = -1;
  final _tichuDecided = <String>{};

  _HeadlessSimulator({
    required this.random,
    required this.targetScore,
    required this.roundsLimit,
    required this.episodes,
    required this.maxStepsPerEpisode,
    required this.outputFormat,
    required this.output,
    required this.includeTimestamps,
    required this.epsilon,
    required this.agentFactory,
    this.episodeOffset = 0,
    this.dealSeed,
    this.callEpsilon = 0,
    this.schupfEpsilon = 0,
    this.shadowHeuristic = false,
    this.skipPlayRows = false,
    this.counterfactualCalls = false,
    this.counterfactualRate = 1,
  });

  Future<GameAction?> _shadowHeuristicTurn(
    final GameSnapshot snapshot,
    final String playerId,
  ) async {
    final agent = _shadowAgents.putIfAbsent(
      playerId,
      () => SmartAiAgent(playerId),
    );
    try {
      return await agent.selectTurn(snapshot);
      // Agents signal "no legal action" with StateError.
      // ignore: avoid_catching_errors
    } on StateError {
      return null;
    }
  }

  Future<void> run() async {
    for (var episode = 0; episode < episodes; episode++) {
      await _runEpisode(episodeOffset + episode + 1);
    }
  }

  Future<void> _runEpisode(final int episodeNumber) async {
    final players = _buildAutomatedPlayers();
    final agents = {
      for (final player in players)
        player.id: agentFactory(player.id, player.seat),
    };
    final engine = GameEngineImpl(
      random: dealSeed == null
          ? random
          : Random(_mixSeed(dealSeed!, episodeNumber)),
    );
    final state = engine.createGame(
      gameId: 'headless_episode_$episodeNumber',
      players: players,
      targetScore: targetScore,
    );
    engine.startGame(state);

    final csvWriter =
        outputFormat == _HeadlessOutputFormat.csv && output != null
        ? _CsvEventWriter(output: output!, includeTimestamps: includeTimestamps)
        : null;
    final bcWriter =
        outputFormat == _HeadlessOutputFormat.bcJsonl && output != null
        ? _BcTransitionWriter(output: output!, episode: episodeNumber)
        : null;
    _bcWriter = bcWriter;
    _tichuDecided.clear();
    final summaryWriter =
        outputFormat == _HeadlessOutputFormat.summary && output != null
        ? _SummaryWriter(output: output!, episode: episodeNumber)
        : null;

    var snapshot = engine.buildSnapshot(state);
    csvWriter?.processSnapshot(snapshot);

    var completedRounds = 0;
    var steps = 0;

    while (true) {
      if (snapshot.scoreState.gameComplete ||
          (roundsLimit != null && completedRounds >= roundsLimit!)) {
        summaryWriter?.emit(snapshot);
        bcWriter?.emitEpisodeEnd(snapshot);
        return;
      }

      if (snapshot.scoreState.roundComplete) {
        engine.startNewRound(state);
        snapshot = engine.buildSnapshot(state);
        csvWriter?.processSnapshot(snapshot);
        continue;
      }

      if (steps >= maxStepsPerEpisode) {
        throw StateError(
          'Episode $episodeNumber exceeded max steps ($maxStepsPerEpisode).',
        );
      }

      final action = await _selectAction(
        engine: engine,
        state: state,
        snapshot: snapshot,
        agents: agents,
      );

      if (action == null) {
        stderr.writeln(
          'warning,episode_abandoned,$episodeNumber,'
          'step=$steps,player=${snapshot.currentPlayerId}',
        );
        summaryWriter?.emit(snapshot);
        bcWriter?.emitEpisodeEnd(snapshot);
        return;
      }

      final explored = _lastActionExplored;
      final shadow =
          shadowHeuristic && (action is PlayTurnAction || action is PassAction)
          ? await _shadowHeuristicTurn(snapshot, action.playerId)
          : null;
      final before = snapshot;
      final appliedAction = _applyActionWithRecovery(
        engine: engine,
        state: state,
        snapshot: snapshot,
        selectedAction: action,
      );
      steps++;

      if (appliedAction is PlayTurnAction || appliedAction is PassAction) {
        csvWriter?.emitOpponentAction(snapshot: before, action: appliedAction);
      }

      snapshot = engine.buildSnapshot(state);
      csvWriter?.processSnapshot(snapshot);
      if (!skipPlayRows) {
        bcWriter?.emitTransition(
          before: before,
          action: appliedAction,
          explored: explored,
          shadow: shadow,
        );
      }

      if (!before.scoreState.roundComplete &&
          snapshot.scoreState.roundComplete) {
        completedRounds++;
        bcWriter?.emitRoundEnd(snapshot, cardsLeftAtFirstOut: _cardsAtFirstOut);
        _cardsAtFirstOut = null;
      } else if (_cardsAtFirstOut == null &&
          snapshot.scoreState.finishOrder.isNotEmpty) {
        // Remember how close everyone was when the first player went out.
        _cardsAtFirstOut = {
          for (final p in snapshot.players)
            p.seat: (snapshot.hands[p.id] ?? const <Card>[]).length,
        };
      }
    }
  }

  /// SplitMix-style mix of (seed, episode) into a 32-bit Random seed.
  static int _mixSeed(final int seed, final int episode) {
    var z = (seed * 0x9E3779B1 + episode * 0x85EBCA77) & 0xFFFFFFFF;
    z = ((z ^ (z >> 16)) * 0x7FEB352D) & 0xFFFFFFFF;
    z = ((z ^ (z >> 15)) * 0x846CA68B) & 0xFFFFFFFF;
    return z ^ (z >> 16);
  }
}
