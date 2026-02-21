import 'dart:async';
import 'dart:math';

import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';
import 'package:tichu/game/turn/tichu_data.dart';

class LocalGameBackend implements GameBackend {
  final GameEngine _engine;
  final Map<String, _LocalGameState> _games = {};
  final Map<String, PlayerAgent> _automatedAgents = {};
  final Set<String> _automatedTurnsInFlight = {};
  Duration _automatedActionDelay = const Duration(seconds: 1);

  LocalGameBackend({
    final GameEngine? engine,
    final Random? random,
    final Map<String, PlayerAgent>? automatedAgents,
  }) : _engine = engine ?? GameEngineImpl(random: random) {
    if (automatedAgents != null) {
      _automatedAgents.addAll(automatedAgents);
    }
  }

  @override
  Stream<PlayerSnapshot> watchGame(final String gameId, final String playerId) {
    final state = _games[gameId];
    if (state == null) {
      throw StateError('Unknown gameId: $gameId');
    }
    return state.controller.stream.map(
      (final snapshot) => _engine.buildPlayerSnapshot(snapshot, playerId),
    );
  }

  @override
  Future<void> setAutomatedActionDelay(final Duration delay) async {
    _automatedActionDelay = delay;
  }

  Stream<GameSnapshot> watchGameState(final String gameId) {
    final state = _games[gameId];
    if (state == null) {
      throw StateError('Unknown gameId: $gameId');
    }
    return state.controller.stream;
  }

  @override
  Future<String> createGame(
    final List<GamePlayer> players, {
    final int targetScore = 1000,
  }) async {
    final gameId = DateTime.now().millisecondsSinceEpoch.toString();
    final engineState = _engine.createGame(
      gameId: gameId,
      players: players,
      targetScore: targetScore,
    );
    final state = _LocalGameState(engineState: engineState);

    _ensureAutomatedAgents(players);

    _games[gameId] = state;
    _emitSnapshot(state);
    return gameId;
  }

  @override
  Future<void> startNewRound(final String gameId) async {
    final state = _games[gameId];
    if (state == null) {
      throw StateError('Unknown gameId: $gameId');
    }
    _engine.startNewRound(state.engineState);
    _clearPendingOpponentTurn(state);

    _emitSnapshot(state);
    await _maybeRunAutomatedPlayers(state);
  }

  @override
  Future<void> startGame(final String gameId) async {
    final state = _games[gameId];
    if (state == null) {
      throw StateError('Unknown gameId: $gameId');
    }
    _engine.startGame(state.engineState);
    _clearPendingOpponentTurn(state);
    _emitSnapshot(state);
    await _maybeRunAutomatedPlayers(state);
  }

  @override
  Future<void> submitAction(
    final String gameId,
    final GameAction action,
  ) async {
    final state = _games[gameId];
    if (state == null) {
      throw StateError('Unknown gameId: $gameId');
    }

    if (state.opponentAwaitingConfirmation &&
        action is! ConfirmOpponentTurnAction &&
        action is! AcknowledgeSchupfAction &&
        action is! CallTichuAction) {
      throw StateError('Confirm the pending opponent turn before continuing.');
    }

    if (action is ConfirmOpponentTurnAction) {
      if (!state.opponentAwaitingConfirmation ||
          state.pendingOpponentAction == null) {
        return;
      }
      final pendingAction = state.pendingOpponentAction!;
      _clearPendingOpponentTurn(state);
      _engine.applyAction(state.engineState, pendingAction);
      _emitSnapshot(state);
      await _maybeRunAutomatedPlayers(state);
      return;
    }
    _engine.applyAction(state.engineState, action);

    if (action is PlayTurnAction || action is PassAction) {
      state.opponentAwaitingConfirmation =
          state.engineState.pendingDragonGiveBy == null &&
          _engine.shouldPauseForAutomatedOpponent(
            state.engineState,
            action.playerId,
          );
    }

    _emitSnapshot(state);
    await _maybeRunAutomatedPlayers(state);
  }

  @override
  Future<void> disposeGame(final String gameId) async {
    final state = _games.remove(gameId);
    await state?.controller.close();
  }

  void _emitSnapshot(final _LocalGameState state) {
    state.controller.add(_buildSnapshot(state));
  }

  GameSnapshot _buildSnapshot(final _LocalGameState state) =>
      _engine.buildSnapshot(
        state.engineState,
        pendingOpponentPlayerId: state.pendingOpponentPlayerId,
        pendingOpponentCards: state.pendingOpponentCards,
        pendingOpponentPass: state.pendingOpponentPass,
        opponentAwaitingConfirmation: state.opponentAwaitingConfirmation,
      );

  void _ensureAutomatedAgents(final List<GamePlayer> players) {
    for (final player in players) {
      if (player.type == PlayerType.automated &&
          !_automatedAgents.containsKey(player.id)) {
        _automatedAgents[player.id] = SmartAiAgent(player.id);
      }
    }
  }

  Future<void> _maybeRunAutomatedPlayers(final _LocalGameState state) async {
    if (state.engineState.scoreTracker.state.roundComplete) {
      return;
    }

    final automatedReceiptsResolved =
        await _resolveSchupfReceiptsForAutomatedPlayers(state);
    if (automatedReceiptsResolved) {
      _emitSnapshot(state);
    }

    if (_engine.hasPendingHumanSchupfReceipts(state.engineState)) {
      return;
    }

    if (state.engineState.phase == GamePhase.grandTichu) {
      await _resolveGrandTichuForAutomatedPlayers(state);
      _emitSnapshot(state);
      if (state.engineState.phase != GamePhase.grandTichu) {
        await _maybeRunAutomatedPlayers(state);
      }
      return;
    }

    if (state.engineState.phase == GamePhase.schupf) {
      await _resolveSchupfForAutomatedPlayers(state);
      _emitSnapshot(state);
      if (state.engineState.phase != GamePhase.schupf) {
        await _maybeRunAutomatedPlayers(state);
      }
      return;
    }

    if (state.opponentAwaitingConfirmation) {
      return;
    }

    if (state.pendingOpponentAction != null) {
      return;
    }

    if (state.engineState.pendingDragonGiveBy != null) {
      final pendingId = state.engineState.pendingDragonGiveBy!;
      final pendingPlayer = state.engineState.players.firstWhere(
        (final p) => p.id == pendingId,
      );
      if (pendingPlayer.type == PlayerType.automated) {
        _autoResolveDragonGive(state, pendingId);
        _emitSnapshot(state);
        if (state.engineState.pendingDragonGiveBy == null) {
          await _maybeRunAutomatedPlayers(state);
        }
      }
      return;
    }

    final currentPlayer =
        state.engineState.players[state.engineState.currentPlayerIndex];
    final agent = _automatedAgents[currentPlayer.id];
    if (agent == null) return;

    final inFlightKey = '${state.engineState.gameId}:${currentPlayer.id}';
    if (_automatedTurnsInFlight.contains(inFlightKey)) return;

    _automatedTurnsInFlight.add(inFlightKey);
    try {
      final snapshot = _buildSnapshot(state);
      final action = await agent.selectAction(snapshot);
      state.pendingOpponentAction = action;
      state.pendingOpponentPlayerId = currentPlayer.id;
      state.pendingOpponentCards
        ..clear()
        ..addAll(action is PlayTurnAction ? action.cards : const <Card>[]);
      state.pendingOpponentPass = action is PassAction;
      state.opponentAwaitingConfirmation = true;
      _emitSnapshot(state);
    } finally {
      _automatedTurnsInFlight.remove(inFlightKey);
    }
  }

  Future<void> _resolveGrandTichuForAutomatedPlayers(
    final _LocalGameState state,
  ) async {
    while (state.engineState.phase == GamePhase.grandTichu) {
      final currentPlayer =
          state.engineState.players[state.engineState.currentPlayerIndex];

      if (state.engineState.grandTichuDecisions.containsKey(currentPlayer.id)) {
        state.engineState.currentPlayerIndex =
            (state.engineState.currentPlayerIndex + 1) %
            state.engineState.players.length;
        continue;
      }

      if (currentPlayer.type != PlayerType.automated) {
        return;
      }

      final agent = _automatedAgents[currentPlayer.id];
      if (agent == null) {
        return;
      }

      final snapshot = _buildSnapshot(state);
      final shouldCall = await agent.shouldCallGrandTichu(snapshot);
      if (state.engineState.phase != GamePhase.grandTichu) {
        return;
      }

      _engine.applyAction(
        state.engineState,
        GrandTichuDecisionAction(playerId: currentPlayer.id, call: shouldCall),
      );
    }
  }

  Future<void> _resolveSchupfForAutomatedPlayers(
    final _LocalGameState state,
  ) async {
    final snapshot = _buildSnapshot(state);
    for (final player in state.engineState.players) {
      if (state.engineState.phase != GamePhase.schupf) {
        return;
      }
      if (player.type != PlayerType.automated) continue;
      if (state.engineState.schupfSelections.containsKey(player.id)) {
        continue;
      }
      final agent = _automatedAgents[player.id];
      if (agent == null) continue;
      final selection = await agent.selectSchupfCards(snapshot);
      if (state.engineState.phase != GamePhase.schupf) {
        return;
      }
      state.pendingOpponentPlayerId = player.id;
      state.pendingOpponentCards
        ..clear()
        ..addAll([selection.toLeft, selection.toPartner, selection.toRight]);
      state.pendingOpponentPass = false;
      state.opponentAwaitingConfirmation = false;
      _emitSnapshot(state);
      await _waitForAutomatedActionDelay();
      if (state.engineState.phase != GamePhase.schupf) {
        return;
      }
      if (state.pendingOpponentPlayerId == player.id) {
        state.pendingOpponentPlayerId = null;
        state.pendingOpponentCards.clear();
        state.pendingOpponentPass = false;
      }
      _engine.applyAction(state.engineState, selection);
    }
  }

  Future<bool> _resolveSchupfReceiptsForAutomatedPlayers(
    final _LocalGameState state,
  ) async {
    var applied = false;
    for (final player in state.engineState.players) {
      if (player.type != PlayerType.automated) continue;
      final receipts = state.engineState.schupfReceipts[player.id];
      if (receipts == null || receipts.isEmpty) continue;
      await _waitForAutomatedActionDelay();
      final currentReceipts = state.engineState.schupfReceipts[player.id];
      if (currentReceipts == null || currentReceipts.isEmpty) {
        continue;
      }
      _engine.applyAction(
        state.engineState,
        AcknowledgeSchupfAction(playerId: player.id),
      );
      applied = true;
    }
    return applied;
  }

  Future<void> _waitForAutomatedActionDelay() async {
    if (_automatedActionDelay <= Duration.zero) return;
    await Future<void>.delayed(_automatedActionDelay);
  }

  void _autoResolveDragonGive(
    final _LocalGameState state,
    final String winnerId,
  ) {
    final opponentIds = _engine.opponentIds(state.engineState, winnerId);
    if (opponentIds.isEmpty) {
      return;
    }

    final agent = _automatedAgents[winnerId];
    final snapshot = _buildSnapshot(state);
    final seat = agent?.selectDragonGive(snapshot);
    final target = state.engineState.players.firstWhere(
      (final player) => player.seat == seat,
      orElse: () => state.engineState.players.firstWhere(
        (final player) => opponentIds.contains(player.id),
      ),
    );
    final targetId = opponentIds.contains(target.id)
        ? target.id
        : opponentIds.first;

    _engine.applyAction(
      state.engineState,
      GiveDragonAction(playerId: winnerId, targetPlayerId: targetId),
    );
  }

  void _clearPendingOpponentTurn(final _LocalGameState state) {
    state.pendingOpponentAction = null;
    state.pendingOpponentPlayerId = null;
    state.pendingOpponentCards.clear();
    state.pendingOpponentPass = false;
    state.opponentAwaitingConfirmation = false;
  }
}

class _LocalGameState {
  final GameEngineState engineState;
  final StreamController<GameSnapshot> controller;

  GameAction? pendingOpponentAction;
  String? pendingOpponentPlayerId;
  final List<Card> pendingOpponentCards = [];
  bool pendingOpponentPass = false;
  bool opponentAwaitingConfirmation = false;

  _LocalGameState({required this.engineState})
    : controller = StreamController<GameSnapshot>.broadcast();
}
