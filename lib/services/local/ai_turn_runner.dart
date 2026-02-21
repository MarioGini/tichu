import 'dart:async';

import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'package:tichu/services/local/local_game_state.dart';

/// Factory that creates a [PlayerAgent] for the given player ID.
typedef AgentFactory = PlayerAgent Function(String playerId);

/// Orchestrates AI agent turns within a local game.
///
/// Manages automated player agents, translates their decisions into engine
/// actions, and exposes a single [runAutomatedPlayers] entry point so that
/// the local backend stays focused on the GameBackend interface.
class AiTurnRunner {
  AiTurnRunner({required final AgentFactory agentFactory})
    : _agentFactory = agentFactory;

  final AgentFactory _agentFactory;

  late GameEngine _engine;

  // ignore: avoid_setters_without_getters, engine is write-only; set once by LocalGameBackend.
  set engine(final GameEngine value) => _engine = value;

  final Map<String, PlayerAgent> _automatedAgents = {};
  final Set<String> _automatedTurnsInFlight = {};
  Duration automatedActionDelay = const Duration(seconds: 1);

  void addAgents(final Map<String, PlayerAgent> agents) =>
      _automatedAgents.addAll(agents);

  /// Ensures every automated player has a registered agent.
  void ensureAgents(final List<GamePlayer> players) {
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
    final LocalGameState state, {
    required final GameSnapshot Function() buildSnapshot,
    required final void Function() emitSnapshot,
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
        (final p) => p.id == pendingId,
      );
      if (pendingPlayer.type == PlayerType.automated) {
        _autoResolveDragonGive(state, pendingId, buildSnapshot);
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
      final action = await agent.selectAction(snapshot);
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

  // ── Grand Tichu ─────────────────────────────────────────────────────

  Future<void> _resolveGrandTichu(
    final LocalGameState state,
    final GameSnapshot Function() buildSnapshot,
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

      if (currentPlayer.type != PlayerType.automated) return;

      final agent = _automatedAgents[currentPlayer.id];
      if (agent == null) return;

      final snapshot = buildSnapshot();
      final shouldCall = await agent.shouldCallGrandTichu(snapshot);
      if (state.engineState.phase != GamePhase.grandTichu) return;

      _engine.applyAction(
        state.engineState,
        GrandTichuDecisionAction(playerId: currentPlayer.id, call: shouldCall),
      );
    }
  }

  // ── Schupf ──────────────────────────────────────────────────────────

  Future<void> _resolveSchupf(
    final LocalGameState state,
    final GameSnapshot Function() buildSnapshot,
    final void Function() emitSnapshot,
  ) async {
    final snapshot = buildSnapshot();
    for (final player in state.engineState.players) {
      if (state.engineState.phase != GamePhase.schupf) return;
      if (player.type != PlayerType.automated) continue;
      if (state.engineState.schupfSelections.containsKey(player.id)) continue;

      final agent = _automatedAgents[player.id];
      if (agent == null) continue;

      final selection = await agent.selectSchupfCards(snapshot);
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

  void _autoResolveDragonGive(
    final LocalGameState state,
    final String winnerId,
    final GameSnapshot Function() buildSnapshot,
  ) {
    final opponentIds = _engine.opponentIds(state.engineState, winnerId);
    if (opponentIds.isEmpty) return;

    final agent = _automatedAgents[winnerId];
    final snapshot = buildSnapshot();
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

  // ── Helpers ─────────────────────────────────────────────────────────

  Future<void> _waitForDelay() async {
    if (automatedActionDelay <= Duration.zero) return;
    await Future<void>.delayed(automatedActionDelay);
  }
}
