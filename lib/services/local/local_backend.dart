import 'dart:async';
import 'dart:math';

import 'package:tichu/game/game_backend.dart';
import 'package:tichu/agents/opponents/default_opponent_agent.dart';
import 'package:tichu/agents/opponents/opponent_agent.dart';
import 'package:tichu/game/engine.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';
import 'package:tichu/game/turn/tichu_data.dart';

class LocalGameBackend implements GameBackend {
  final GameEngine _engine;
  final Map<String, _LocalGameState> _games = {};
  final Map<String, OpponentAgent> _automatedAgents = {};
  final Set<String> _automatedTurnsInFlight = {};

  LocalGameBackend({
    GameEngine? engine,
    Random? random,
    Map<String, OpponentAgent>? automatedAgents,
  }) : _engine = engine ?? GameEngineImpl(random: random) {
    if (automatedAgents != null) {
      _automatedAgents.addAll(automatedAgents);
    }
  }

  @override
  Stream<PlayerSnapshot> watchGame(String gameId, String playerId) {
    final state = _games[gameId];
    if (state == null) {
      throw StateError('Unknown gameId: $gameId');
    }
    return state.controller.stream.map(
      (snapshot) => _engine.buildPlayerSnapshot(snapshot, playerId),
    );
  }

  Stream<GameSnapshot> watchGameState(String gameId) {
    final state = _games[gameId];
    if (state == null) {
      throw StateError('Unknown gameId: $gameId');
    }
    return state.controller.stream;
  }

  @override
  Future<String> createGame(
    List<GamePlayer> players, {
    int targetScore = 1000,
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
    _maybeRunAutomatedOpponents(state);
    return gameId;
  }

  @override
  Future<void> startNewRound(String gameId) async {
    final state = _games[gameId];
    if (state == null) {
      throw StateError('Unknown gameId: $gameId');
    }
    _engine.startNewRound(state.engineState);
    _clearPendingOpponentTurn(state);

    _emitSnapshot(state);
    _maybeRunAutomatedOpponents(state);
  }

  @override
  Future<void> startGame(String gameId) async {
    final state = _games[gameId];
    if (state == null) {
      throw StateError('Unknown gameId: $gameId');
    }
    _engine.startGame(state.engineState);
    _clearPendingOpponentTurn(state);
    _emitSnapshot(state);
    _maybeRunAutomatedOpponents(state);
  }

  @override
  Future<void> submitAction(String gameId, GameAction action) async {
    final state = _games[gameId];
    if (state == null) {
      throw StateError('Unknown gameId: $gameId');
    }

    if (state.opponentAwaitingConfirmation &&
        action is! ConfirmOpponentTurnAction &&
        action is! AcknowledgeSchupfAction) {
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
      _maybeRunAutomatedOpponents(state);
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
    _maybeRunAutomatedOpponents(state);
  }

  @override
  Future<void> disposeGame(String gameId) async {
    final state = _games.remove(gameId);
    await state?.controller.close();
  }

  void _emitSnapshot(_LocalGameState state) {
    state.controller.add(_buildSnapshot(state));
  }

  GameSnapshot _buildSnapshot(_LocalGameState state) {
    return _engine.buildSnapshot(
      state.engineState,
      pendingOpponentPlayerId: state.pendingOpponentPlayerId,
      pendingOpponentCards: state.pendingOpponentCards,
      pendingOpponentPass: state.pendingOpponentPass,
      opponentAwaitingConfirmation: state.opponentAwaitingConfirmation,
    );
  }

  void _ensureAutomatedAgents(List<GamePlayer> players) {
    for (final player in players) {
      if (player.type == PlayerType.automated &&
          !_automatedAgents.containsKey(player.id)) {
        _automatedAgents[player.id] = DefaultOpponentAgent(player.id);
      }
    }
  }

  Future<void> _maybeRunAutomatedOpponents(_LocalGameState state) async {
    if (state.engineState.scoreTracker.state.roundComplete) {
      return;
    }

    if (_engine.hasPendingHumanSchupfReceipts(state.engineState)) {
      return;
    }

    if (state.engineState.phase == GamePhase.grandTichu) {
      await _resolveGrandTichuForAutomatedOpponents(state);
      _emitSnapshot(state);
      if (state.engineState.phase != GamePhase.grandTichu) {
        _maybeRunAutomatedOpponents(state);
      }
      return;
    }

    if (state.engineState.phase == GamePhase.schupf) {
      await _resolveSchupfForAutomatedOpponents(state);
      _emitSnapshot(state);
      if (state.engineState.phase != GamePhase.schupf) {
        _maybeRunAutomatedOpponents(state);
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
        (p) => p.id == pendingId,
      );
      if (pendingPlayer.type == PlayerType.automated) {
        _autoResolveDragonGive(state, pendingId);
        _emitSnapshot(state);
        if (state.engineState.pendingDragonGiveBy == null) {
          _maybeRunAutomatedOpponents(state);
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

  Future<void> _resolveGrandTichuForAutomatedOpponents(
    _LocalGameState state,
  ) async {
    final snapshot = _buildSnapshot(state);
    for (final player in state.engineState.players) {
      if (state.engineState.phase != GamePhase.grandTichu) {
        return;
      }
      if (player.type != PlayerType.automated) continue;
      if (state.engineState.grandTichuDecisions.containsKey(player.id)) {
        continue;
      }
      final agent = _automatedAgents[player.id];
      if (agent == null) continue;
      final shouldCall = await agent.shouldCallGrandTichu(snapshot);
      if (state.engineState.phase != GamePhase.grandTichu) {
        return;
      }
      _engine.applyAction(
        state.engineState,
        GrandTichuDecisionAction(playerId: player.id, call: shouldCall),
      );
    }
  }

  Future<void> _resolveSchupfForAutomatedOpponents(
    _LocalGameState state,
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
      _engine.applyAction(state.engineState, selection);
    }
  }

  void _autoResolveDragonGive(_LocalGameState state, String winnerId) {
    final opponentIds = _engine.opponentIds(state.engineState, winnerId);
    if (opponentIds.isEmpty) {
      return;
    }

    final agent = _automatedAgents[winnerId];
    final snapshot = _buildSnapshot(state);
    final seat = agent?.selectDragonGive(snapshot);
    final target = state.engineState.players.firstWhere(
      (player) => player.seat == seat,
      orElse: () => state.engineState.players.firstWhere(
        (player) => opponentIds.contains(player.id),
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

  void _clearPendingOpponentTurn(_LocalGameState state) {
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
