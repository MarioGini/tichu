import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/engine_state.dart';

void applyGrandTichuDecision(
  GameEngineState state,
  GrandTichuDecisionAction action,
) {
  if (state.grandTichuDecisions.containsKey(action.playerId)) {
    return;
  }

  state.grandTichuDecisions[action.playerId] = action.call;
  if (action.call) {
    state.scoreTracker.recordTichuCall(action.playerId, isGrand: true);
  }

  if (_allPlayersDecided(state)) {
    _maybeFinalizeGrandTichu(state);
    return;
  }

  state.currentPlayerIndex =
      (state.currentPlayerIndex + 1) % state.players.length;
}

bool _allPlayersDecided(GameEngineState state) {
  return state.grandTichuDecisions.length >= state.players.length;
}

void _maybeFinalizeGrandTichu(GameEngineState state) {
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
