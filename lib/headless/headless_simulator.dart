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

  /// Omit play/pass rows from bc-jsonl (call / schupf / round data only).
  final bool skipPlayRows;
  final _shadowAgents = <String, SmartAiAgent>{};

  /// Set by [_selectAction] when the returned action came from ε-exploration.
  var _lastActionExplored = false;

  _BcTransitionWriter? _bcWriter;
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

      if (appliedAction is PassAction) {
        _notifyIsmctsPass(
          agents: agents,
          passPlayerId: appliedAction.playerId,
          deckTurn: before.deck.turn,
        );
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
        bcWriter?.emitRoundEnd(snapshot);
      }
    }
  }

  Future<GameAction?> _selectAction({
    required final GameEngine engine,
    required final GameEngineState state,
    required final GameSnapshot snapshot,
    required final Map<String, PlayerAgent> agents,
  }) async {
    _lastActionExplored = false;
    final round = state.scoreTracker.state.roundNumber;
    if (round != _preSchupfRound) {
      _preSchupfRound = round;
      _preSchupfDecided.clear();
    }
    var request = AgentDecisions.next(
      engine,
      state,
      preSchupfDecided: _preSchupfDecided,
    );
    // Pre-schupf Tichu: every player decides before anyone passes.
    while (request is PreSchupfTichuRequest) {
      final playerId = request.playerId;
      _preSchupfDecided.add(playerId);
      final agent = agents[playerId];
      if (agent == null) {
        throw StateError('No agent registered for $playerId.');
      }
      var shouldCall = await agent.shouldCallTichuBeforeSchupf(snapshot);
      final explored = callEpsilon > 0 && random.nextDouble() < callEpsilon;
      if (explored) shouldCall = !shouldCall;
      _bcWriter?.emitCallDecision(
        kind: 'pre',
        snapshot: snapshot,
        playerId: playerId,
        called: shouldCall,
        explored: explored,
      );
      if (shouldCall) return CallTichuAction(playerId: playerId);
      request = AgentDecisions.next(
        engine,
        state,
        preSchupfDecided: _preSchupfDecided,
      );
    }
    if (request == null) {
      throw StateError('No pending decision in phase ${state.phase}.');
    }
    final agent = agents[request.playerId];
    if (agent == null) {
      throw StateError('No agent registered for ${request.playerId}.');
    }

    // Training-only hooks around the shared decision logic: exploration of
    // calls / schupf / plays, and logging of call and schupf decisions.
    switch (request) {
      case GrandTichuRequest(:final playerId):
        var shouldCall = await agent.shouldCallGrandTichu(snapshot);
        final explored = callEpsilon > 0 && random.nextDouble() < callEpsilon;
        if (explored) shouldCall = !shouldCall;
        _bcWriter?.emitCallDecision(
          kind: 'grand',
          snapshot: snapshot,
          playerId: playerId,
          called: shouldCall,
          explored: explored,
        );
        return GrandTichuDecisionAction(playerId: playerId, call: shouldCall);
      case SchupfRequest(:final playerId):
        var selection = await agent.selectSchupfCards(snapshot);
        final explored =
            schupfEpsilon > 0 && random.nextDouble() < schupfEpsilon;
        if (explored) {
          selection = _perturbSchupf(
            selection,
            snapshot.hands[playerId] ?? const <Card>[],
          );
        }
        _bcWriter?.emitSchupfDecision(
          snapshot: snapshot,
          action: selection,
          explored: explored,
        );
        return selection;
      case TurnRequest(:final playerId):
        return _selectTurn(
          snapshot: snapshot,
          playerId: playerId,
          agent: agent,
        );
      case SchupfReceiptRequest() ||
          DragonGiveRequest() ||
          PreSchupfTichuRequest():
        return AgentDecisions.resolve(request, agent, snapshot, state);
    }
  }

  Future<GameAction?> _selectTurn({
    required final GameSnapshot snapshot,
    required final String playerId,
    required final PlayerAgent agent,
  }) async {
    if (epsilon > 0 && random.nextDouble() < epsilon) {
      final randomAction = _pickRandomLegalAction(snapshot, playerId);
      if (randomAction != null) {
        _lastActionExplored = true;
        return randomAction;
      }
    }

    try {
      final tichuKey = '${snapshot.scoreState.roundNumber}:$playerId';
      if ((snapshot.canCallTichuByPlayer[playerId] ?? false) &&
          (snapshot.scoreState.tichuCalls[playerId] ?? TichuCall.none) ==
              TichuCall.none &&
          _tichuDecided.add(tichuKey)) {
        // First Tichu opportunity this round: explore + log the decision.
        var shouldCall = await agent.shouldCallTichu(snapshot);
        final explored = callEpsilon > 0 && random.nextDouble() < callEpsilon;
        if (explored) shouldCall = !shouldCall;
        _bcWriter?.emitCallDecision(
          kind: 'tichu',
          snapshot: snapshot,
          playerId: playerId,
          called: shouldCall,
          explored: explored,
        );
        if (shouldCall) return CallTichuAction(playerId: playerId);
        return await agent.selectTurn(snapshot);
      }
      return await agent.selectAction(snapshot);
      // Agents signal "no legal action" with StateError.
      // ignore: avoid_catching_errors
    } on StateError {
      return null;
    }
  }

  /// Replace one to three (mostly one) of the passed cards with random other
  /// hand cards, and sometimes swap destinations.
  SchupfAction _perturbSchupf(final SchupfAction base, final List<Card> hand) {
    final chosen = [base.toLeft, base.toPartner, base.toRight];
    // Mostly small changes, so the data covers choices near the heuristic's.
    final roll = random.nextDouble();
    final changes = roll < 0.7 ? 1 : (roll < 0.95 ? 2 : 3);
    final slots = [0, 1, 2]..shuffle(random);
    for (final slot in slots.take(changes)) {
      final pool = [
        for (final c in hand)
          if (!chosen.any((final x) => _sameCard(x, c))) c,
      ];
      if (pool.isEmpty) break;
      chosen[slot] = pool[random.nextInt(pool.length)];
    }
    if (random.nextBool()) {
      // Also explore who gets which card.
      final a = random.nextInt(3);
      final b = random.nextInt(3);
      final t = chosen[a];
      chosen[a] = chosen[b];
      chosen[b] = t;
    }
    return SchupfAction(
      playerId: base.playerId,
      toLeft: chosen[0],
      toPartner: chosen[1],
      toRight: chosen[2],
    );
  }

  static bool _sameCard(final Card a, final Card b) =>
      a.face == b.face && a.color == b.color;

  GameAction? _pickRandomLegalAction(
    final GameSnapshot snapshot,
    final String playerId,
  ) {
    final hand = List<Card>.from(snapshot.hands[playerId] ?? const <Card>[]);
    if (hand.isEmpty) return null;

    final legalTurns = generateLegalTurns(snapshot.deck, List<Card>.from(hand));

    // Honour any active wish: if the wish must be fulfilled and this turn
    // doesn't fulfil it, skip it. mahJong() returns true when the wish is
    // active and the turn fails to satisfy it.
    final wishFiltered = <TichuTurn>[
      for (final turn in legalTurns)
        if (!mahJong(snapshot.deck, turn, hand)) turn,
    ];

    // Pass legality also requires non-empty deck and that the wish (if any)
    // does not need to be fulfilled by this player on this turn.
    final canPass =
        snapshot.deck.turn.type != TurnType.empty &&
        snapshot.deck.turn.type != TurnType.none &&
        !mahJong(snapshot.deck, TichuTurn(TurnType.none, const []), hand);

    final actions = <GameAction>[
      for (final turn in wishFiltered)
        PlayTurnAction(playerId: playerId, cards: List<Card>.from(turn.cards)),
      if (canPass) PassAction(playerId: playerId),
    ];

    if (actions.isEmpty) return null;
    return actions[random.nextInt(actions.length)];
  }

  GameAction _applyActionWithRecovery({
    required final GameEngine engine,
    required final GameEngineState state,
    required final GameSnapshot snapshot,
    required final GameAction selectedAction,
  }) {
    final normalizedSelectedAction = _normalizeActionForEngine(selectedAction);
    _assertActionLegal(snapshot: snapshot, action: normalizedSelectedAction);
    engine.applyAction(state, normalizedSelectedAction);
    return normalizedSelectedAction;
  }

  GameAction _normalizeActionForEngine(final GameAction action) {
    if (action is PlayTurnAction) {
      return PlayTurnAction(
        playerId: action.playerId,
        cards: List<Card>.from(action.cards),
        inputWish: action.inputWish,
      );
    }
    return action;
  }

  void _assertActionLegal({
    required final GameSnapshot snapshot,
    required final GameAction action,
  }) {
    if (action is PlayTurnAction) {
      _assertPlayActionLegal(snapshot: snapshot, action: action);
      return;
    }
    if (action is PassAction) {
      _assertPassActionLegal(snapshot: snapshot, action: action);
    }
  }

  void _assertPlayActionLegal({
    required final GameSnapshot snapshot,
    required final PlayTurnAction action,
  }) {
    if (snapshot.phase != GamePhase.play) {
      throw StateError('Illegal play action outside play phase.');
    }
    if (action.playerId != snapshot.currentPlayerId) {
      throw StateError('Illegal play action by non-current player.');
    }

    final hand = List<Card>.from(
      snapshot.hands[action.playerId] ?? const <Card>[],
    );
    if (!_handContainsAllCards(hand: hand, cards: action.cards)) {
      throw StateError('Illegal play action: cards not in hand.');
    }

    late final TichuTurn turn;
    try {
      turn = getTurn(List<Card>.from(action.cards));
    } on Exception {
      throw StateError('Illegal play action: invalid turn shape.');
    }
    if (turn.type == TurnType.none) {
      throw StateError('Illegal play action: invalid turn shape.');
    }
    if (mahJong(snapshot.deck, turn, hand)) {
      throw StateError('Illegal play action: wish must be fulfilled.');
    }
    if (!validTurn(snapshot.deck.turn, turn)) {
      throw StateError('Illegal play action: does not beat current deck turn.');
    }
  }

  void _assertPassActionLegal({
    required final GameSnapshot snapshot,
    required final PassAction action,
  }) {
    if (snapshot.phase != GamePhase.play) {
      throw StateError('Illegal pass action outside play phase.');
    }
    if (action.playerId != snapshot.currentPlayerId) {
      throw StateError('Illegal pass action by non-current player.');
    }

    final hand = List<Card>.from(
      snapshot.hands[action.playerId] ?? const <Card>[],
    );
    if (!_canPass(snapshot: snapshot, hand: hand)) {
      throw StateError('Illegal pass action for current deck/hand state.');
    }
  }

  bool _handContainsAllCards({
    required final List<Card> hand,
    required final List<Card> cards,
  }) {
    final temp = List<Card>.from(hand);
    for (final card in cards) {
      final index = temp.indexWhere((final candidate) {
        if (card.face == CardFace.phoenix) {
          return candidate.face == CardFace.phoenix;
        }
        return candidate.face == card.face && candidate.color == card.color;
      });
      if (index < 0) return false;
      temp.removeAt(index);
    }
    return true;
  }

  bool _canPass({
    required final GameSnapshot snapshot,
    required final List<Card> hand,
  }) {
    if (snapshot.deck.turn.type == TurnType.empty ||
        snapshot.deck.turn.type == TurnType.none) {
      return false;
    }
    return !mahJong(snapshot.deck, TichuTurn(TurnType.none, const []), hand);
  }

  void _notifyIsmctsPass({
    required final Map<String, PlayerAgent> agents,
    required final String passPlayerId,
    required final TichuTurn deckTurn,
  }) {
    for (final agent in agents.values) {
      if (agent is SmartAiAgent) {
        final strategy = agent.playSelectionStrategy;
        if (strategy is IsmctsPlaySelectionStrategy) {
          strategy.recordPass(passPlayerId: passPlayerId, deckTurn: deckTurn);
        }
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
