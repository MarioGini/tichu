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
  /// (`shadow_index` in bc-jsonl).
  final bool shadowHeuristic;

  /// Label each logged Tichu decision with its exact counterfactual value
  /// (round forked and played both ways), see [_counterfactualCall].
  final bool counterfactualCalls;

  /// Share of call decisions that get a counterfactual label (each label
  /// replays the rest of the round twice, so labelling every decision makes
  /// games ~30x slower).
  final double counterfactualRate;

  /// Guessed deals per Tichu label for the decision-time simulation
  /// estimate (`--pimc-worlds`, see [_counterfactualCall]).
  final int pimcWorlds;

  /// Runs the endgame search of agents that have one (null = no agent has).
  final EndgameSearcher? endgameSearcher;

  /// Branch details of the last [_counterfactualCall] (see there).
  Map<String, Object?>? _lastCallDetails;

  bool _labelCounterfactual() =>
      counterfactualCalls &&
      _bcWriter != null &&
      (counterfactualRate >= 1 || random.nextDouble() < counterfactualRate);

  /// Share of the learner seats' play decisions that get exact rollout
  /// values for every legal action (see [_rolloutValues]). When positive,
  /// only labelled play rows are written.
  final double rolloutRate;
  final int rolloutMaxActions;

  /// Worlds per labelled decision (`--rollout-worlds=K`, default 1 = the
  /// real deal only): K - 1 re-dealt worlds are rolled out too and written
  /// as `q_rollout_worlds`, for decisions with at least [worldsMinCards]
  /// cards in hand.
  final int rolloutWorlds;

  /// Share of Dragon gifts and Mah Jong wishes labelled with every option
  /// played out (`--side-rollout-rate`, default 0).
  final double sideRolloutRate;
  final int worldsMinCards;

  /// Label only decisions with at most this many cards in hand
  /// (`--label-max-cards`, default 14 = all; e.g. 5 for an endgame review).
  final int labelMaxCards;

  final bool Function(int seat) isLearnerSeat;

  /// Add a human-readable description of the position to labelled rows.
  final bool describe;

  /// Heuristic variants whose choice is logged on every labelled row
  /// (`shadow_indices`), so one rollout dataset gives the exact one-step
  /// value of each variant.
  final List<HeuristicOptions> shadowVariants;

  /// Share of schupf decisions labelled with exact candidate values.
  final double schupfRolloutRate;
  final int schupfCandidates;

  /// Write a compact record of every round (`--record-games`, bc-jsonl).
  final bool recordGames;
  _GameRecorder? _recorder;

  /// Schupf labels draw candidates from the extended set.
  final bool schupfExtended;

  /// Schupf labels keep only partner cards this convention allows (the
  /// labelled team's convention).
  final PartnerConvention schupfConvention;
  late final List<Map<String, SmartAiAgent>> _variantAgents = [
    for (final _ in shadowVariants) <String, SmartAiAgent>{},
  ];

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
    this.rolloutRate = 0,
    this.rolloutMaxActions = 12,
    this.rolloutWorlds = 1,
    this.sideRolloutRate = 0,
    this.worldsMinCards = 0,
    this.labelMaxCards = 14,
    this.isLearnerSeat = _everySeat,
    this.describe = false,
    this.shadowVariants = const [],
    this.schupfRolloutRate = 0,
    this.schupfCandidates = 16,
    this.recordGames = false,
    this.schupfExtended = false,
    this.schupfConvention = PartnerConvention.free,
    this.pimcWorlds = 0,
    this.endgameSearcher,
  });

  static bool _everySeat(int _) => true;

  Future<GameAction?> _shadowHeuristicTurn(
    GameSnapshot snapshot,
    String playerId,
  ) async {
    final agent = _shadowAgents.putIfAbsent(
      playerId,
      () => SmartAiAgent(playerId),
    );
    return await agent.selectTurn(snapshot);
  }

  /// What each shadow variant would play in [snapshot] (null = no move).
  Future<List<GameAction?>> _variantTurns(
    GameSnapshot snapshot,
    String playerId,
  ) async {
    final turns = <GameAction?>[];
    for (var i = 0; i < shadowVariants.length; i++) {
      final agent = _variantAgents[i].putIfAbsent(
        playerId,
        () => SmartAiAgent(playerId, options: shadowVariants[i]),
      );
      turns.add(await agent.selectTurn(snapshot));
    }
    return turns;
  }

  Future<void> run() async {
    for (var episode = 0; episode < episodes; episode++) {
      await _runEpisode(episodeOffset + episode + 1);
      // The game loop never yields to the event loop, so without this the
      // sink would buffer the whole run in memory.
      await output?.flush();
    }
    final searcher = endgameSearcher;
    if (searcher != null) {
      final ms = searcher.stopwatch.elapsedMicroseconds / 1000;
      stderr.writeln(
        jsonEncode({
          'endgame_search_stats': true,
          'episodes': episodes,
          'searches': searcher.searches,
          'switches': searcher.switches,
          'rollouts': searcher.rollouts,
          'solves': searcher.solves,
          'solve_switches': searcher.solveSwitches,
          'solve_give_ups': searcher.solveGiveUps,
          'search_ms': ms.round(),
          'ms_per_search': searcher.searches == 0 ? 0 : ms / searcher.searches,
        }),
      );
    }
  }

  /// Rollout labelling is on (only labelled play rows are written).
  bool get _rolloutLabelling => rolloutRate > 0;

  Future<void> _runEpisode(int episodeNumber) async {
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
    _recorder = recordGames && outputFormat == _HeadlessOutputFormat.bcJsonl
        ? (_GameRecorder()..startRound(state))
        : null;

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
        _recorder?.startRound(state);
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
      ({List<double?> diff, List<double?> own})? rollouts;
      List<List<double?>>? worlds;
      if (_rolloutLabelling &&
          bcWriter != null &&
          (action is PlayTurnAction || action is PassAction) &&
          isLearnerSeat(
            state.players.firstWhere((p) => p.id == action.playerId).seat,
          )) {
        if (random.nextDouble() < rolloutRate &&
            (snapshot.hands[action.playerId]?.length ?? 0) <= labelMaxCards) {
          rollouts = await _rolloutValues(
            state: state,
            snapshot: snapshot,
            chosen: action,
          );
          if (rollouts != null &&
              rolloutWorlds > 1 &&
              (snapshot.hands[action.playerId]?.length ?? 0) >=
                  worldsMinCards) {
            worlds = await _worldRollouts(state: state, chosen: action);
          }
        }
      }
      await _labelSideDecision(
        state: state,
        snapshot: snapshot,
        action: action,
      );
      final variants = rollouts != null && shadowVariants.isNotEmpty
          ? await _variantTurns(snapshot, action.playerId)
          : null;
      bcWriter?.step = _recorder?.step;
      final appliedAction = _applyActionWithRecovery(
        engine: engine,
        state: state,
        snapshot: snapshot,
        selectedAction: action,
      );
      steps++;
      _recorder?.add(state, appliedAction);

      if (appliedAction is PlayTurnAction || appliedAction is PassAction) {
        csvWriter?.emitOpponentAction(snapshot: before, action: appliedAction);
      }

      snapshot = engine.buildSnapshot(state);
      csvWriter?.processSnapshot(snapshot);
      if (!skipPlayRows && (!_rolloutLabelling || rollouts != null)) {
        bcWriter?.emitTransition(
          before: before,
          action: appliedAction,
          explored: explored,
          shadow: shadow,
          rollouts: rollouts?.diff,
          rolloutsOwn: rollouts?.own,
          rolloutWorlds: worlds,
          describe: describe,
          variants: variants,
        );
      }

      if (!before.scoreState.roundComplete &&
          snapshot.scoreState.roundComplete) {
        completedRounds++;
        final recorder = _recorder;
        if (recorder != null) {
          bcWriter?.output.writeln(
            jsonEncode(recorder.record(episodeNumber, snapshot)),
          );
        }
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
  static int _mixSeed(int seed, int episode) {
    var z = (seed * 0x9E3779B1 + episode * 0x85EBCA77) & 0xFFFFFFFF;
    z = ((z ^ (z >> 16)) * 0x7FEB352D) & 0xFFFFFFFF;
    z = ((z ^ (z >> 15)) * 0x846CA68B) & 0xFFFFFFFF;
    return z ^ (z >> 16);
  }
}
