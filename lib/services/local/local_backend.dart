import 'dart:async';
import 'dart:math';

import 'package:tichu/services/game_backend.dart';
import 'package:tichu/view_model/ai/player_agent.dart';
import 'package:tichu/view_model/ai/smart_ai_agent.dart';
import 'package:tichu/view_model/turn/engine/engine.dart';
import 'package:tichu/view_model/turn/engine/engine_impl.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';

class LocalGameBackend implements GameBackend {
  final GameEngine _engine;
  final Map<String, _LocalGameState> _games = {};
  final Map<String, PlayerAgent> _aiAgents = {};
  final Set<String> _aiInFlight = {};

  LocalGameBackend({
    GameEngine? engine,
    Random? random,
    Map<String, PlayerAgent>? aiAgents,
  }) : _engine = engine ?? GameEngineImpl(random: random) {
    if (aiAgents != null) {
      _aiAgents.addAll(aiAgents);
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

    _ensureAiAgents(players);

    _games[gameId] = state;
    _emitSnapshot(state);
    _maybeRunAi(state);
    return gameId;
  }

  @override
  Future<void> startNewRound(String gameId) async {
    final state = _games[gameId];
    if (state == null) {
      throw StateError('Unknown gameId: $gameId');
    }
    _engine.startNewRound(state.engineState);
    _clearAiState(state);

    _emitSnapshot(state);
    _maybeRunAi(state);
  }

  @override
  Future<void> startGame(String gameId) async {
    final state = _games[gameId];
    if (state == null) {
      throw StateError('Unknown gameId: $gameId');
    }
    _engine.startGame(state.engineState);
    _clearAiState(state);
    _emitSnapshot(state);
    _maybeRunAi(state);
  }

  @override
  Future<void> submitAction(String gameId, GameAction action) async {
    final state = _games[gameId];
    if (state == null) {
      throw StateError('Unknown gameId: $gameId');
    }

    if (state.aiAwaitingConfirmation &&
        action is! ConfirmAiTurnAction &&
        action is! AcknowledgeSchupfAction) {
      throw StateError('Confirm the AI turn before continuing.');
    }

    if (action is ConfirmAiTurnAction) {
      if (!state.aiAwaitingConfirmation || state.pendingAiAction == null) {
        return;
      }
      final pendingAction = state.pendingAiAction!;
      _clearAiState(state);
      _engine.applyAction(state.engineState, pendingAction);
      _emitSnapshot(state);
      _maybeRunAi(state);
      return;
    }
    _engine.applyAction(state.engineState, action);

    if (action is PlayTurnAction || action is PassAction) {
      state.aiAwaitingConfirmation =
          state.engineState.pendingDragonGiveBy == null &&
          _engine.shouldPauseForAi(state.engineState, action.playerId);
    }

    _emitSnapshot(state);
    _maybeRunAi(state);
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
      pendingAiPlayerId: state.pendingAiPlayerId,
      pendingAiCards: state.pendingAiCards,
      pendingAiPass: state.pendingAiPass,
      aiAwaitingConfirmation: state.aiAwaitingConfirmation,
    );
  }

  void _ensureAiAgents(List<GamePlayer> players) {
    for (final player in players) {
      if (player.type == PlayerType.ai && !_aiAgents.containsKey(player.id)) {
        _aiAgents[player.id] = SmartAiAgent(player.id);
      }
    }
  }

  Future<void> _maybeRunAi(_LocalGameState state) async {
    if (state.engineState.scoreTracker.state.roundComplete) {
      return;
    }

    if (_engine.hasPendingHumanSchupfReceipts(state.engineState)) {
      return;
    }

    if (state.engineState.phase == GamePhase.grandTichu) {
      await _resolveGrandTichuForAi(state);
      _emitSnapshot(state);
      if (state.engineState.phase != GamePhase.grandTichu) {
        _maybeRunAi(state);
      }
      return;
    }

    if (state.engineState.phase == GamePhase.schupf) {
      await _resolveSchupfForAi(state);
      _emitSnapshot(state);
      if (state.engineState.phase != GamePhase.schupf) {
        _maybeRunAi(state);
      }
      return;
    }

    if (state.aiAwaitingConfirmation) {
      return;
    }

    if (state.pendingAiAction != null) {
      return;
    }

    if (state.engineState.pendingDragonGiveBy != null) {
      final pendingId = state.engineState.pendingDragonGiveBy!;
      final pendingPlayer = state.engineState.players.firstWhere(
        (p) => p.id == pendingId,
      );
      if (pendingPlayer.type == PlayerType.ai) {
        _autoResolveDragonGive(state, pendingId);
        _emitSnapshot(state);
        if (state.engineState.pendingDragonGiveBy == null) {
          _maybeRunAi(state);
        }
      }
      return;
    }

    final currentPlayer =
        state.engineState.players[state.engineState.currentPlayerIndex];
    final agent = _aiAgents[currentPlayer.id];
    if (agent == null) return;

    final inFlightKey = '${state.engineState.gameId}:${currentPlayer.id}';
    if (_aiInFlight.contains(inFlightKey)) return;

    _aiInFlight.add(inFlightKey);
    try {
      final snapshot = _buildSnapshot(state);
      final action = await agent.selectTurn(snapshot);
      state.pendingAiAction = action;
      state.pendingAiPlayerId = currentPlayer.id;
      state.pendingAiCards
        ..clear()
        ..addAll(action is PlayTurnAction ? action.cards : const <Card>[]);
      state.pendingAiPass = action is PassAction;
      state.aiAwaitingConfirmation = true;
      _emitSnapshot(state);
    } finally {
      _aiInFlight.remove(inFlightKey);
    }
  }

  Future<void> _resolveGrandTichuForAi(_LocalGameState state) async {
    final snapshot = _buildSnapshot(state);
    for (final player in state.engineState.players) {
      if (state.engineState.phase != GamePhase.grandTichu) {
        return;
      }
      if (player.type != PlayerType.ai) continue;
      if (state.engineState.grandTichuDecisions.containsKey(player.id)) {
        continue;
      }
      final agent = _aiAgents[player.id];
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

  Future<void> _resolveSchupfForAi(_LocalGameState state) async {
    final snapshot = _buildSnapshot(state);
    for (final player in state.engineState.players) {
      if (state.engineState.phase != GamePhase.schupf) {
        return;
      }
      if (player.type != PlayerType.ai) continue;
      if (state.engineState.schupfSelections.containsKey(player.id)) {
        continue;
      }
      final agent = _aiAgents[player.id];
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

    final agent = _aiAgents[winnerId];
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

  void _clearAiState(_LocalGameState state) {
    state.pendingAiAction = null;
    state.pendingAiPlayerId = null;
    state.pendingAiCards.clear();
    state.pendingAiPass = false;
    state.aiAwaitingConfirmation = false;
  }
}

class _LocalGameState {
  final GameEngineState engineState;
  final StreamController<GameSnapshot> controller;

  GameAction? pendingAiAction;
  String? pendingAiPlayerId;
  final List<Card> pendingAiCards = [];
  bool pendingAiPass = false;
  bool aiAwaitingConfirmation = false;

  _LocalGameState({required this.engineState})
    : controller = StreamController<GameSnapshot>.broadcast();
}
