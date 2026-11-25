import 'dart:async';

import 'package:tichu/agents/endgame_search.dart';
import 'package:tichu/game/agent_decisions.dart';
import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'package:tichu/services/local/local_game_state.dart';

part 'ai_phase_resolvers.dart';

/// Factory that creates a [PlayerAgent] for the given player ID.
typedef AgentFactory = PlayerAgent Function(String playerId);

/// Orchestrates AI agent turns within a local game.
///
/// Manages automated player agents, translates their decisions into engine
/// actions, and exposes a single [runAutomatedPlayers] entry point so that
/// the local runtime stays focused on state progression.
class AiTurnRunner {
  AiTurnRunner({required this._engine, required this._agentFactory});

  /// The engine of the games this runner plays bots in (the runtime's).
  final GameEngine _engine;
  final AgentFactory _agentFactory;

  /// Endgame search of bots configured with one (see `AppBots`). Rollouts
  /// use fresh bots from the factory for every seat (humans included).
  late final EndgameSearcher _endgameSearcher = EndgameSearcher(
    rolloutAgent: (playerId, _) => _agentFactory(playerId),
    yieldBetweenRollouts: true,
  );

  final Map<String, PlayerAgent> _automatedAgents = {};
  final Set<String> _automatedTurnsInFlight = {};

  /// `gameId:round:playerId` of bots already asked about a pre-schupf Tichu.
  final Set<String> _preSchupfDecided = {};
  Duration automatedActionDelay = const Duration(seconds: 1);

  void addAgents(Map<String, PlayerAgent> agents) =>
      _automatedAgents.addAll(agents);

  /// Ensures every automated player has a registered agent.
  void ensureAgents(List<GamePlayer> players) {
    for (final player in players) {
      if (player.type == PlayerType.automated &&
          !_automatedAgents.containsKey(player.id)) {
        _automatedAgents[player.id] = _agentFactory(player.id);
      }
    }
  }

  /// Run AI turns until no more automated actions are possible.
  ///
  /// Calls [emitSnapshot] after each state-changing step so listeners see
  /// intermediate states.
  Future<void> runAutomatedPlayers(
    LocalGameState state, {
    required GameSnapshot Function() buildSnapshot,
    required void Function() emitSnapshot,
  }) async {
    if (state.engineState.scoreTracker.state.roundComplete) {
      return;
    }

    final receiptsResolved = await _resolveSchupfReceipts(state, buildSnapshot);
    if (receiptsResolved) {
      emitSnapshot();
    }

    if (_engine.hasPendingHumanSchupfReceipts(state.engineState)) {
      return;
    }

    if (state.engineState.phase == GamePhase.grandTichu) {
      await _resolveGrandTichu(state, buildSnapshot);
      emitSnapshot();
      if (state.engineState.phase != GamePhase.grandTichu) {
        await runAutomatedPlayers(
          state,
          buildSnapshot: buildSnapshot,
          emitSnapshot: emitSnapshot,
        );
      }
      return;
    }

    if (state.engineState.phase == GamePhase.schupf) {
      await _resolveSchupf(state, buildSnapshot, emitSnapshot);
      emitSnapshot();
      if (state.engineState.phase != GamePhase.schupf) {
        await runAutomatedPlayers(
          state,
          buildSnapshot: buildSnapshot,
          emitSnapshot: emitSnapshot,
        );
      }
      return;
    }

    if (state.opponentAwaitingConfirmation) return;
    if (state.pendingOpponentAction != null) return;

    if (state.engineState.pendingDragonGiveBy != null) {
      final pendingId = state.engineState.pendingDragonGiveBy!;
      final pendingPlayer = state.engineState.players.firstWhere(
        (p) => p.id == pendingId,
      );
      if (pendingPlayer.type == PlayerType.automated) {
        await _autoResolveDragonGive(state, pendingId, buildSnapshot);
        emitSnapshot();
        if (state.engineState.pendingDragonGiveBy == null) {
          await runAutomatedPlayers(
            state,
            buildSnapshot: buildSnapshot,
            emitSnapshot: emitSnapshot,
          );
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
      final snapshot = buildSnapshot();
      var action = await AgentDecisions.resolve(
        TurnRequest(currentPlayer.id),
        agent,
        snapshot,
        state.engineState,
      );
      if (action != null) {
        final logLength = state.engineState.roundLog.length;
        action = await _endgameSearcher.refine(
          state: state.engineState,
          agent: agent,
          chosen: action,
        );
        // The search yields to the event loop: drop the move if the game
        // moved on meanwhile (e.g. a human bomb). The run that action
        // started may have skipped this bot (its turn was in flight), so
        // run the bots again once the in-flight mark is gone.
        if (state.engineState.roundLog.length != logLength ||
            state
                    .engineState
                    .players[state.engineState.currentPlayerIndex]
                    .id !=
                currentPlayer.id ||
            state.opponentAwaitingConfirmation ||
            state.pendingOpponentAction != null) {
          _automatedTurnsInFlight.remove(inFlightKey);
          await runAutomatedPlayers(
            state,
            buildSnapshot: buildSnapshot,
            emitSnapshot: emitSnapshot,
          );
          return;
        }
      }
      state.pendingOpponentAction = action;
      state.pendingOpponentPlayerId = currentPlayer.id;
      state.pendingOpponentCards
        ..clear()
        ..addAll(action is PlayTurnAction ? action.cards : const <Card>[]);
      state.pendingOpponentPass = action is PassAction;
      state.opponentAwaitingConfirmation = true;
      emitSnapshot();
    } finally {
      _automatedTurnsInFlight.remove(inFlightKey);
    }
  }

  bool _isAutomated(GamePlayer player) => player.type == PlayerType.automated;

  // ── Helpers ─────────────────────────────────────────────────────────

  Future<void> _waitForDelay() async {
    if (automatedActionDelay <= Duration.zero) return;
    await Future<void>.delayed(automatedActionDelay);
  }
}
