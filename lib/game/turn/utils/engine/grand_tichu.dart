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

  _maybeFinalizeGrandTichu(state);
}

void _maybeFinalizeGrandTichu(GameEngineState state) {
  if (state.grandTichuDecisions.length < state.players.length) {
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
