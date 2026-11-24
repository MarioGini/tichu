import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/scoring/score_tracker.dart';

/// A decision the engine is waiting for from one player.
///
/// Shared by every driver of [PlayerAgent]s — the app's `AiTurnRunner` and
/// the headless training simulator — so bots behave identically in the app
/// and in training. Drivers add their own concerns around it (UI delays and
/// confirmation in the app; exploration and logging in training).
sealed class DecisionRequest {
  final String playerId;
  const DecisionRequest(this.playerId);
}

/// The player must acknowledge the cards they received in the schupf.
class SchupfReceiptRequest extends DecisionRequest {
  const SchupfReceiptRequest(super.playerId);
}

/// The player must decide whether to call Grand Tichu (8 cards seen).
class GrandTichuRequest extends DecisionRequest {
  const GrandTichuRequest(super.playerId);
}

/// Before anyone passes cards: may the player call Tichu now (so the
/// partner can react in the exchange)? Only asked when the driver tracks
/// these decisions (`preSchupfDecided` in [AgentDecisions.next]).
class PreSchupfTichuRequest extends DecisionRequest {
  const PreSchupfTichuRequest(super.playerId);
}

/// The player must choose the three cards to pass.
class SchupfRequest extends DecisionRequest {
  const SchupfRequest(super.playerId);
}

/// The player won a trick with the Dragon and must give it away.
class DragonGiveRequest extends DecisionRequest {
  final List<String> opponentIds;
  const DragonGiveRequest(super.playerId, this.opponentIds);
}

/// It is the player's turn in the play phase (play, pass or call Tichu).
class TurnRequest extends DecisionRequest {
  const TurnRequest(super.playerId);
}

abstract final class AgentDecisions {
  /// The next pending decision among players accepted by [include] (all
  /// players when null), or null when none of them has to act.
  ///
  /// In the Grand Tichu phase this advances `state.currentPlayerIndex` past
  /// players who already decided (the engine expects drivers to do so).
  ///
  /// When [preSchupfDecided] is given, every player not in it (and without a
  /// call yet) is first asked a [PreSchupfTichuRequest] in the schupf phase;
  /// the driver adds the player to the set once asked.
  ///
  /// Bots are never offered an out-of-turn bomb (measured: about -50 points
  /// per bomb); only humans in the app bomb out of turn.
  static DecisionRequest? next(
    GameEngine engine,
    GameEngineState state, {
    bool Function(GamePlayer player)? include,
    Set<String>? preSchupfDecided,
  }) {
    bool accepts(GamePlayer p) => include == null || include(p);

    for (final player in state.players) {
      final receipts = state.schupfReceipts[player.id];
      if (receipts != null && receipts.isNotEmpty && accepts(player)) {
        return SchupfReceiptRequest(player.id);
      }
    }

    if (state.phase == GamePhase.grandTichu) {
      for (var i = 0; i < state.players.length; i++) {
        final current = state.players[state.currentPlayerIndex];
        if (!state.grandTichuDecisions.containsKey(current.id)) {
          return accepts(current) ? GrandTichuRequest(current.id) : null;
        }
        state.currentPlayerIndex =
            (state.currentPlayerIndex + 1) % state.players.length;
      }
      return null;
    }
    if (state.phase == GamePhase.schupf) {
      if (preSchupfDecided != null) {
        final calls = state.scoreTracker.state.tichuCalls;
        for (final player in state.players) {
          if (accepts(player) &&
              !preSchupfDecided.contains(player.id) &&
              !state.schupfSelections.containsKey(player.id) &&
              (calls[player.id] ?? TichuCall.none) == TichuCall.none) {
            return PreSchupfTichuRequest(player.id);
          }
        }
      }
      for (final player in state.players) {
        if (!state.schupfSelections.containsKey(player.id) && accepts(player)) {
          return SchupfRequest(player.id);
        }
      }
      return null;
    }

    final dragonBy = state.pendingDragonGiveBy;
    if (dragonBy != null) {
      final player = state.players.firstWhere((p) => p.id == dragonBy);
      if (!accepts(player)) return null;
      return DragonGiveRequest(dragonBy, engine.opponentIds(state, dragonBy));
    }

    if (state.phase != GamePhase.play) return null;
    final current = state.players[state.currentPlayerIndex];
    return accepts(current) ? TurnRequest(current.id) : null;
  }

  /// Ask [agent] for its answer to [request] and return it as an action.
  /// Returns null only for a [PreSchupfTichuRequest] answered with "no".
  ///
  /// May throw [StateError] when the agent has no legal turn.
  static Future<GameAction?> resolve(
    DecisionRequest request,
    PlayerAgent agent,
    GameSnapshot snapshot,
    GameEngineState state,
  ) async {
    switch (request) {
      case SchupfReceiptRequest(:final playerId):
        return AcknowledgeSchupfAction(playerId: playerId);
      case GrandTichuRequest(:final playerId):
        return GrandTichuDecisionAction(
          playerId: playerId,
          call: await agent.shouldCallGrandTichu(snapshot),
        );
      case PreSchupfTichuRequest(:final playerId):
        return await agent.shouldCallTichuBeforeSchupf(snapshot)
            ? CallTichuAction(playerId: playerId)
            : null;
      case SchupfRequest():
        return agent.selectSchupfCards(snapshot);
      case DragonGiveRequest(:final playerId, :final opponentIds):
        return GiveDragonAction(
          playerId: playerId,
          targetPlayerId: dragonTarget(
            state: state,
            opponentIds: opponentIds,
            preferredSeat: agent.selectDragonGive(snapshot),
          ),
        );
      case TurnRequest():
        return agent.selectAction(snapshot);
    }
  }

  /// The opponent sitting at [preferredSeat], or the first opponent when the
  /// seat is not an opponent's.
  static String dragonTarget({
    required GameEngineState state,
    required List<String> opponentIds,
    required int? preferredSeat,
  }) {
    if (opponentIds.isEmpty) {
      throw StateError('No valid dragon target available.');
    }
    for (final player in state.players) {
      if (player.seat == preferredSeat && opponentIds.contains(player.id)) {
        return player.id;
      }
    }
    return opponentIds.first;
  }
}
