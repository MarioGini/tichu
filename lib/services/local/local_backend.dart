import 'dart:async';
import 'dart:math';

import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';

import 'package:tichu/services/local/ai_turn_runner.dart';
import 'package:tichu/services/local/local_game_state.dart';

/// A fully local, in-process [GameBackend] implementation.
///
/// Runs the engine directly and delegates AI agent orchestration to
/// [AiTurnRunner].
class LocalGameBackend implements GameBackend {
  final GameEngine _engine;
  final AiTurnRunner _aiRunner;
  final Map<String, LocalGameState> _games = {};

  LocalGameBackend({
    final GameEngine? engine,
    final Random? random,
    final AgentFactory? agentFactory,
    final Map<String, PlayerAgent>? automatedAgents,
  }) : _engine = engine ?? GameEngineImpl(random: random),
       _aiRunner = AiTurnRunner(
         agentFactory: agentFactory ?? SmartAiAgent.new,
       ) {
    _aiRunner.engine = _engine;
    if (automatedAgents != null) {
      _aiRunner.addAgents(automatedAgents);
    }
  }

  @override
  Stream<PlayerSnapshot> watchGame(final String gameId, final String playerId) {
    final state = _requireGame(gameId);
    return state.controller.stream.map(
      (final snapshot) => _engine.buildPlayerSnapshot(snapshot, playerId),
    );
  }

  @override
  Future<void> setAutomatedActionDelay(final Duration delay) async {
    _aiRunner.automatedActionDelay = delay;
  }

  Stream<GameSnapshot> watchGameState(final String gameId) =>
      _requireGame(gameId).controller.stream;

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
    final state = LocalGameState(engineState: engineState);
    _aiRunner.ensureAgents(players);
    _games[gameId] = state;
    _emitSnapshot(state);
    return gameId;
  }

  @override
  Future<void> startNewRound(final String gameId) async {
    final state = _requireGame(gameId);
    _engine.startNewRound(state.engineState);
    _clearPendingOpponentTurn(state);
    _emitSnapshot(state);
    await _runAi(state);
  }

  @override
  Future<void> startGame(final String gameId) async {
    final state = _requireGame(gameId);
    _engine.startGame(state.engineState);
    _clearPendingOpponentTurn(state);
    _emitSnapshot(state);
    await _runAi(state);
  }

  @override
  Future<void> submitAction(
    final String gameId,
    final GameAction action,
  ) async {
    final state = _requireGame(gameId);

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

  @override
  Future<void> disposeGame(final String gameId) async {
    final state = _games.remove(gameId);
    await state?.controller.close();
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  LocalGameState _requireGame(final String gameId) {
    final state = _games[gameId];
    if (state == null) throw StateError('Unknown gameId: $gameId');
    return state;
  }

  void _emitSnapshot(final LocalGameState state) =>
      state.controller.add(_buildSnapshot(state));

  GameSnapshot _buildSnapshot(final LocalGameState state) =>
      _engine.buildSnapshot(
        state.engineState,
        pendingOpponentPlayerId: state.pendingOpponentPlayerId,
        pendingOpponentCards: state.pendingOpponentCards,
        pendingOpponentPass: state.pendingOpponentPass,
        opponentAwaitingConfirmation: state.opponentAwaitingConfirmation,
      );

  Future<void> _runAi(final LocalGameState state) =>
      _aiRunner.runAutomatedPlayers(
        state,
        buildSnapshot: () => _buildSnapshot(state),
        emitSnapshot: () => _emitSnapshot(state),
      );

  void _clearPendingOpponentTurn(final LocalGameState state) {
    state.pendingOpponentAction = null;
    state.pendingOpponentPlayerId = null;
    state.pendingOpponentCards.clear();
    state.pendingOpponentPass = false;
    state.opponentAwaitingConfirmation = false;
  }
}
