import 'package:tichu/game/engine_state.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/scoring/score_tracker.dart';

void applyGrandTichuDecision(
  final GameEngineState state,
  final GrandTichuDecisionAction action,
) {
  if (state.grandTichuDecisions.containsKey(action.playerId)) {
    return;
  }

  final canCallGrand =
      action.call && !_partnerAlreadyCalledGrandTichu(state, action.playerId);

  state.grandTichuDecisions[action.playerId] = canCallGrand;
  if (canCallGrand) {
    state.scoreTracker.recordTichuCall(action.playerId, isGrand: true);
  }

  if (_allPlayersDecided(state)) {
    _maybeFinalizeGrandTichu(state);
    return;
  }

  state.currentPlayerIndex =
      (state.currentPlayerIndex + 1) % state.players.length;
}

bool _partnerAlreadyCalledGrandTichu(final GameEngineState state, final String playerId) {
  final player = _playerById(state, playerId);
  if (player == null) {
    return false;
  }

  for (final other in state.players) {
    if (other.id == playerId) {
      continue;
    }
    if (other.seat % 2 != player.seat % 2) {
      continue;
    }
    final call = state.scoreTracker.state.tichuCalls[other.id];
    if (call == TichuCall.grandTichu) {
      return true;
    }
  }

  return false;
}

GamePlayer? _playerById(final GameEngineState state, final String playerId) {
  for (final player in state.players) {
    if (player.id == playerId) {
      return player;
    }
  }
  return null;
}

bool _allPlayersDecided(final GameEngineState state) => state.grandTichuDecisions.length >= state.players.length;

void _maybeFinalizeGrandTichu(final GameEngineState state) {
  if (!_allPlayersDecided(state)) {
    return;
  }

  for (final player in state.players) {
    final extras = state.reservedHands[player.id];
    if (extras == null || extras.isEmpty) continue;
    final hand = state.hands[player.id];
    if (hand != null) {
      hand.addAll(extras);
    }
  }
  state.reservedHands.clear();
  state.phase = GamePhase.schupf;
  state.schupfSelections.clear();
}
