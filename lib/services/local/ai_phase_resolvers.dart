part of 'ai_turn_runner.dart';

/// Bot decisions outside the play phase: Grand Tichu, schupf, receipts and
/// the Dragon gift.
extension _PhaseResolvers on AiTurnRunner {
  // ── Grand Tichu ─────────────────────────────────────────────────────

  Future<void> _resolveGrandTichu(
    final LocalGameState state,
    final GameSnapshot Function() buildSnapshot,
  ) async {
    while (state.engineState.phase == GamePhase.grandTichu) {
      final request = AgentDecisions.next(
        _engine,
        state.engineState,
        include: _isAutomated,
      );
      if (request is! GrandTichuRequest) return;

      final agent = _automatedAgents[request.playerId];
      if (agent == null) return;

      final action = await AgentDecisions.resolve(
        request,
        agent,
        buildSnapshot(),
        state.engineState,
      );
      if (state.engineState.phase != GamePhase.grandTichu) return;

      _engine.applyAction(state.engineState, action!);
    }
  }

  // ── Schupf ──────────────────────────────────────────────────────────

  Future<void> _resolveSchupf(
    final LocalGameState state,
    final GameSnapshot Function() buildSnapshot,
    final void Function() emitSnapshot,
  ) async {
    // Bots may announce Tichu before anyone passes, so partners can react
    // in the exchange (same decision order as in headless training).
    final round = state.engineState.scoreTracker.state.roundNumber;
    final decided = <String>{
      for (final key in _preSchupfDecided)
        if (key.startsWith('${state.engineState.gameId}:$round:'))
          key.split(':').last,
    };
    while (true) {
      final request = AgentDecisions.next(
        _engine,
        state.engineState,
        include: _isAutomated,
        preSchupfDecided: decided,
      );
      if (request is! PreSchupfTichuRequest) break;
      decided.add(request.playerId);
      _preSchupfDecided.add(
        '${state.engineState.gameId}:$round:${request.playerId}',
      );
      final agent = _automatedAgents[request.playerId];
      if (agent == null) continue;
      final call = await AgentDecisions.resolve(
        request,
        agent,
        buildSnapshot(),
        state.engineState,
      );
      if (call != null) _engine.applyAction(state.engineState, call);
    }

    final snapshot = buildSnapshot();
    for (final player in state.engineState.players) {
      if (state.engineState.phase != GamePhase.schupf) return;
      if (player.type != PlayerType.automated) continue;
      if (state.engineState.schupfSelections.containsKey(player.id)) continue;

      final agent = _automatedAgents[player.id];
      if (agent == null) continue;

      final selection =
          (await AgentDecisions.resolve(
                SchupfRequest(player.id),
                agent,
                snapshot,
                state.engineState,
              ))!
              as SchupfAction;
      if (state.engineState.phase != GamePhase.schupf) return;

      state.pendingOpponentPlayerId = player.id;
      state.pendingOpponentCards
        ..clear()
        ..addAll([selection.toLeft, selection.toPartner, selection.toRight]);
      state.pendingOpponentPass = false;
      state.opponentAwaitingConfirmation = false;
      emitSnapshot();

      await _waitForDelay();
      if (state.engineState.phase != GamePhase.schupf) return;
      if (state.pendingOpponentPlayerId == player.id) {
        state.pendingOpponentPlayerId = null;
        state.pendingOpponentCards.clear();
        state.pendingOpponentPass = false;
      }
      _engine.applyAction(state.engineState, selection);
    }
  }

  // ── Schupf receipts ─────────────────────────────────────────────────

  Future<bool> _resolveSchupfReceipts(
    final LocalGameState state,
    final GameSnapshot Function() buildSnapshot,
  ) async {
    var applied = false;
    for (final player in state.engineState.players) {
      if (player.type != PlayerType.automated) continue;
      final receipts = state.engineState.schupfReceipts[player.id];
      if (receipts == null || receipts.isEmpty) continue;
      await _waitForDelay();
      final currentReceipts = state.engineState.schupfReceipts[player.id];
      if (currentReceipts == null || currentReceipts.isEmpty) continue;
      _engine.applyAction(
        state.engineState,
        AcknowledgeSchupfAction(playerId: player.id),
      );
      applied = true;
    }
    return applied;
  }

  // ── Dragon give ─────────────────────────────────────────────────────

  Future<void> _autoResolveDragonGive(
    final LocalGameState state,
    final String winnerId,
    final GameSnapshot Function() buildSnapshot,
  ) async {
    final opponentIds = _engine.opponentIds(state.engineState, winnerId);
    if (opponentIds.isEmpty) return;
    final agent = _automatedAgents[winnerId];
    if (agent == null) return;

    final action = await AgentDecisions.resolve(
      DragonGiveRequest(winnerId, opponentIds),
      agent,
      buildSnapshot(),
      state.engineState,
    );
    _engine.applyAction(state.engineState, action!);
  }
}
