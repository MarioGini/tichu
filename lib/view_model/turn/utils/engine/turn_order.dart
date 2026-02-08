import 'package:tichu/view_model/turn/engine/engine_state.dart';

void advanceToNextPlayer(GameEngineState state) {
  state.currentPlayerIndex = nextActiveIndex(state, state.currentPlayerIndex);
}

int nextActiveIndex(GameEngineState state, int startIndex) {
  final total = state.players.length;
  var next = (startIndex + 1) % total;
  while (state.finishedPlayers.contains(state.players[next].id)) {
    next = (next + 1) % total;
    if (next == startIndex) {
      break;
    }
  }
  return next;
}

int partnerIndex(int index) {
  return (index + 2) % 4;
}

int playerIndexById(GameEngineState state, String playerId) {
  return state.players.indexWhere((player) => player.id == playerId);
}

List<String> opponentIdsForPlayer(GameEngineState state, String playerId) {
  final player = state.players.firstWhere((p) => p.id == playerId);
  return state.players
      .where((p) => p.id != playerId && (p.seat % 2 != player.seat % 2))
      .map((p) => p.id)
      .toList();
}
