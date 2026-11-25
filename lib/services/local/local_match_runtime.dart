import 'dart:async';
import 'dart:math';

import 'package:tichu/agents/app_bots.dart';
import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_exceptions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/record/game_record.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';
import 'package:tichu/services/local/ai_turn_runner.dart';
import 'package:tichu/services/local/local_game_state.dart';
import 'package:tichu/services/request_rejected_exception.dart';

/// Fully local, in-process runtime for a single match.
///
/// This owns engine state and AI orchestration but does not expose any UI-
/// facing transport contract. Higher-level services adapt it into the
/// session/match APIs.
class LocalMatchRuntime {
  final GameEngine _engine;
  final AiTurnRunner _aiRunner;
  final Map<String, LocalGameState> _games = {};

  LocalMatchRuntime({
    GameEngine? engine,
    Random? random,
    AgentFactory? agentFactory,
    Map<String, PlayerAgent>? automatedAgents,
  }) : this._(
         engine ?? GameEngineImpl(random: random),
         agentFactory ?? AppBots.current.build,
         automatedAgents,
       );

  LocalMatchRuntime._(
    this._engine,
    AgentFactory agentFactory,
    Map<String, PlayerAgent>? automatedAgents,
  ) : _aiRunner = AiTurnRunner(engine: _engine, agentFactory: agentFactory) {
    if (automatedAgents != null) {
      _aiRunner.addAgents(automatedAgents);
    }
  }

  Future<void> setAutomatedActionDelay(Duration delay) async {
    _aiRunner.automatedActionDelay = delay;
  }

  Stream<GameSnapshot> watchGameState(String gameId) =>
      _requireGame(gameId).watchSnapshots();

  Future<String> createGame(
    List<GamePlayer> players, {
    int targetScore = 1000,
  }) async {
    // A UUID, so a stored game record can be looked up by the match id.
    final gameId = generateUuidV4();
    final engineState = _engine.createGame(
      gameId: gameId,
      players: players,
      targetScore: targetScore,
    );
    final state = LocalGameState(engineState: engineState);
    _aiRunner.ensureAgents(players);
    _games[gameId] = state;
    _emitSnapshot(state);
    return gameId;
  }

  Future<void> startNewRound(String gameId) async {
    final state = _requireGame(gameId);
    _engine.startNewRound(state.engineState);
    _clearPendingOpponentTurn(state);
    _emitSnapshot(state);
    await _runAi(state);
  }

  Future<void> startGame(String gameId) async {
    final state = _requireGame(gameId);
    _engine.startGame(state.engineState);
    _clearPendingOpponentTurn(state);
    _emitSnapshot(state);
    await _runAi(state);
  }

  Future<void> submitAction(String gameId, GameAction action) async {
    final state = _requireGame(gameId);

    if (state.opponentAwaitingConfirmation &&
        action is! ConfirmOpponentTurnAction &&
        action is! AcknowledgeSchupfAction &&
        action is! CallTichuAction) {
      throw const IllegalActionException(
        'Confirm the pending opponent turn before continuing.',
      );
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
      await _runAi(state);
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
    await _runAi(state);
  }

  Future<void> disposeGame(String gameId) async {
    final state = _games.remove(gameId);
    await state?.controller.close();
  }

  LocalGameState _requireGame(String gameId) {
    final state = _games[gameId];
    if (state == null) {
      throw RequestRejectedException('Unknown gameId: $gameId');
    }
    return state;
  }

  void _emitSnapshot(LocalGameState state) {
    final snapshot = _buildSnapshot(state);
    state.latestSnapshot = snapshot;
    state.controller.add(snapshot);
  }

  GameSnapshot _buildSnapshot(LocalGameState state) => _engine.buildSnapshot(
    state.engineState,
    pendingOpponentPlayerId: state.pendingOpponentPlayerId,
    pendingOpponentCards: state.pendingOpponentCards,
    pendingOpponentPass: state.pendingOpponentPass,
    opponentAwaitingConfirmation: state.opponentAwaitingConfirmation,
  );

  Future<void> _runAi(LocalGameState state) => _aiRunner.runAutomatedPlayers(
    state,
    buildSnapshot: () => _buildSnapshot(state),
    emitSnapshot: () => _emitSnapshot(state),
  );

  void _clearPendingOpponentTurn(LocalGameState state) {
    state.pendingOpponentAction = null;
    state.pendingOpponentPlayerId = null;
    state.pendingOpponentCards.clear();
    state.pendingOpponentPass = false;
    state.opponentAwaitingConfirmation = false;
  }
}
