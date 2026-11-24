part of 'headless.dart';

/// Asks the bots for each pending decision, with exploration on top.
extension _Decisions on _HeadlessSimulator {
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
        counterfactual: _labelCounterfactual()
            ? await _counterfactualCall(engine, state, playerId, 'pre')
            : null,
        cfDetails: _lastCallDetails,
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
          counterfactual: _labelCounterfactual()
              ? await _counterfactualCall(engine, state, playerId, 'grand')
              : null,
          cfDetails: _lastCallDetails,
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
        if (schupfRolloutRate > 0) {
          if (random.nextDouble() < schupfRolloutRate) {
            await _labelSchupf(
              engine: engine,
              state: state,
              snapshot: snapshot,
              playerId: playerId,
              chosen: selection,
            );
          }
        } else {
          _bcWriter?.emitSchupfDecision(
            snapshot: snapshot,
            action: selection,
            explored: explored,
          );
        }
        return selection;
      case TurnRequest(:final playerId):
        final turn = await _selectTurn(
          engine: engine,
          state: state,
          snapshot: snapshot,
          playerId: playerId,
          agent: agent,
        );
        final searcher = endgameSearcher;
        if (turn == null || searcher == null || _lastActionExplored) {
          return turn;
        }
        return searcher.refine(
          state: state,
          agent: agent,
          chosen: turn,
        );
      case DragonGiveRequest():
        final gift = await AgentDecisions.resolve(
          request,
          agent,
          snapshot,
          state,
        );
        final searcher = endgameSearcher;
        if (gift is! GiveDragonAction || searcher == null) return gift;
        return searcher.refineDragonGift(
          state: state,
          agent: agent,
          chosen: gift,
        );
      case SchupfReceiptRequest() || PreSchupfTichuRequest():
        return AgentDecisions.resolve(request, agent, snapshot, state);
    }
  }

  Future<GameAction?> _selectTurn({
    required final GameEngine engine,
    required final GameEngineState state,
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
      final canCall =
          (snapshot.canCallTichuByPlayer[playerId] ?? false) &&
          (snapshot.scoreState.tichuCalls[playerId] ?? TichuCall.none) ==
              TichuCall.none &&
          !_tichuDecided.contains(tichuKey);
      // The bot decides when it plays its first card; a pass keeps the
      // option (see SmartAiAgent.selectAction).
      GameAction? turn;
      if (canCall && agent is SmartAiAgent) {
        turn = await agent.selectTurn(snapshot);
        if (turn is PassAction) return turn;
      }
      if (canCall && _tichuDecided.add(tichuKey)) {
        // The Tichu decision of this round: explore + log it.
        var shouldCall = await agent.shouldCallTichu(snapshot);
        final explored = callEpsilon > 0 && random.nextDouble() < callEpsilon;
        if (explored) shouldCall = !shouldCall;
        _bcWriter?.emitCallDecision(
          kind: 'tichu',
          snapshot: snapshot,
          playerId: playerId,
          called: shouldCall,
          explored: explored,
          counterfactual: _labelCounterfactual()
              ? await _counterfactualCall(engine, state, playerId, 'tichu')
              : null,
          cfDetails: _lastCallDetails,
        );
        if (shouldCall) return CallTichuAction(playerId: playerId);
        return turn ?? await agent.selectTurn(snapshot);
      }
      return await agent.selectAction(snapshot);
      // Agents signal "no legal action" with StateError.
      // ignore: avoid_catching_errors
    } on StateError {
      return null;
    }
  }
}
