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
  final bool includeLegalTurnCount;
  final double epsilon;
  final PlayerAgent Function(String playerId, int seat) agentFactory;

  _HeadlessSimulator({
    required this.random,
    required this.targetScore,
    required this.roundsLimit,
    required this.episodes,
    required this.maxStepsPerEpisode,
    required this.outputFormat,
    required this.output,
    required this.includeTimestamps,
    required this.includeLegalTurnCount,
    required this.epsilon,
    required this.agentFactory,
  });

  Future<void> run() async {
    for (var episode = 0; episode < episodes; episode++) {
      await _runEpisode(episode + 1);
    }
  }

  Future<void> _runEpisode(final int episodeNumber) async {
    final players = _buildAutomatedPlayers();
    final agents = {
      for (final player in players)
        player.id: agentFactory(player.id, player.seat),
    };
    final engine = GameEngineImpl(random: random);
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
    final rlWriter =
        outputFormat == _HeadlessOutputFormat.rlJsonl && output != null
        ? _RlTransitionWriter(
            output: output!,
            episode: episodeNumber,
            includeLegalTurnCount: includeLegalTurnCount,
          )
        : null;

    var snapshot = engine.buildSnapshot(state);
    csvWriter?.processSnapshot(snapshot);

    var completedRounds = 0;
    var steps = 0;

    while (true) {
      if (snapshot.scoreState.gameComplete) {
        return;
      }
      if (roundsLimit != null && completedRounds >= roundsLimit!) {
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
        return;
      }

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
        _notifyMctsPass(
          agents: agents,
          passPlayerId: appliedAction.playerId,
          deckTurn: before.deck.turn,
        );
      }

      snapshot = engine.buildSnapshot(state);
      csvWriter?.processSnapshot(snapshot);
      rlWriter?.emitTransition(
        before: before,
        action: appliedAction,
        after: snapshot,
        step: steps,
      );

      if (!before.scoreState.roundComplete &&
          snapshot.scoreState.roundComplete) {
        completedRounds++;
      }
    }
  }

  Future<GameAction?> _selectAction({
    required final GameEngine engine,
    required final GameEngineState state,
    required final GameSnapshot snapshot,
    required final Map<String, PlayerAgent> agents,
  }) async {
    final receiptPlayerId = _nextReceiptPlayerId(state);
    if (receiptPlayerId != null) {
      return AcknowledgeSchupfAction(playerId: receiptPlayerId);
    }

    if (state.phase == GamePhase.grandTichu) {
      final currentPlayer = state.players[state.currentPlayerIndex];
      if (state.grandTichuDecisions.containsKey(currentPlayer.id)) {
        state.currentPlayerIndex =
            (state.currentPlayerIndex + 1) % state.players.length;
        return _selectAction(
          engine: engine,
          state: state,
          snapshot: snapshot,
          agents: agents,
        );
      }

      final agent = agents[currentPlayer.id];
      if (agent == null) {
        throw StateError('No agent registered for ${currentPlayer.id}.');
      }

      if (epsilon > 0 && random.nextDouble() < epsilon) {
        return GrandTichuDecisionAction(
          playerId: currentPlayer.id,
          call: random.nextBool(),
        );
      }

      final shouldCall = await agent.shouldCallGrandTichu(snapshot);
      return GrandTichuDecisionAction(
        playerId: currentPlayer.id,
        call: shouldCall,
      );
    }

    if (state.phase == GamePhase.schupf) {
      for (final player in state.players) {
        if (state.schupfSelections.containsKey(player.id)) {
          continue;
        }
        final agent = agents[player.id];
        if (agent == null) {
          throw StateError('No agent registered for ${player.id}.');
        }
        return agent.selectSchupfCards(snapshot);
      }
      throw StateError('Schupf phase active but no player can schupfen.');
    }

    if (state.pendingDragonGiveBy != null) {
      final winnerId = state.pendingDragonGiveBy!;
      final opponentIds = engine.opponentIds(state, winnerId);
      if (opponentIds.isEmpty) {
        throw StateError('No valid dragon target available for $winnerId.');
      }

      if (epsilon > 0 && random.nextDouble() < epsilon) {
        final randomTarget = opponentIds[random.nextInt(opponentIds.length)];
        return GiveDragonAction(
          playerId: winnerId,
          targetPlayerId: randomTarget,
        );
      }

      final preferredSeat = agents[winnerId]?.selectDragonGive(snapshot);
      final targetId = _resolveDragonTarget(
        state: state,
        opponentIds: opponentIds,
        preferredSeat: preferredSeat,
      );

      return GiveDragonAction(playerId: winnerId, targetPlayerId: targetId);
    }

    final currentPlayer = state.players[state.currentPlayerIndex];
    final agent = agents[currentPlayer.id];
    if (agent == null) {
      throw StateError('No agent registered for ${currentPlayer.id}.');
    }

    if (epsilon > 0 &&
        snapshot.phase == GamePhase.play &&
        random.nextDouble() < epsilon) {
      final randomAction = _pickRandomLegalAction(snapshot, currentPlayer.id);
      if (randomAction != null) {
        return randomAction;
      }
    }

    try {
      return await agent.selectAction(snapshot);
    } on StateError {
      return null;
    }
  }

  GameAction? _pickRandomLegalAction(
    final GameSnapshot snapshot,
    final String playerId,
  ) {
    final hand = List<Card>.from(snapshot.hands[playerId] ?? const <Card>[]);
    if (hand.isEmpty) return null;

    final legalTurns = generateLegalTurns(snapshot.deck, List<Card>.from(hand));
    final canPass =
        snapshot.deck.turn.type != TurnType.empty &&
        snapshot.deck.turn.type != TurnType.none &&
        !mahJong(snapshot.deck, TichuTurn(TurnType.none, const []), hand);

    final actions = <GameAction>[
      for (final turn in legalTurns)
        PlayTurnAction(
          playerId: playerId,
          cards: List<Card>.from(turn.cards),
          inputWish: CardFace.none,
        ),
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

  String? _nextReceiptPlayerId(final GameEngineState state) {
    for (final player in state.players) {
      final receipts = state.schupfReceipts[player.id];
      if (receipts != null && receipts.isNotEmpty) return player.id;
    }
    return null;
  }

  String _resolveDragonTarget({
    required final GameEngineState state,
    required final List<String> opponentIds,
    required final int? preferredSeat,
  }) {
    if (preferredSeat != null) {
      for (final player in state.players) {
        if (player.seat == preferredSeat && opponentIds.contains(player.id)) {
          return player.id;
        }
      }
    }
    return opponentIds.first;
  }

  void _notifyMctsPass({
    required final Map<String, PlayerAgent> agents,
    required final String passPlayerId,
    required final TichuTurn deckTurn,
  }) {
    for (final agent in agents.values) {
      if (agent is SmartAiAgent) {
        final strategy = agent.playSelectionStrategy;
        if (strategy is MctsPlaySelectionStrategy) {
          strategy.recordPass(passPlayerId: passPlayerId, deckTurn: deckTurn);
        }
        if (strategy is IsmctsPlaySelectionStrategy) {
          strategy.recordPass(passPlayerId: passPlayerId, deckTurn: deckTurn);
        }
      }
    }
  }
}
