import 'package:tichu/game/engine_state.dart';

void advanceToNextPlayer(final GameEngineState state) {
  state.currentPlayerIndex = nextActiveIndex(state, state.currentPlayerIndex);
}

int nextActiveIndex(final GameEngineState state, final int startIndex) {
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

int partnerIndex(final int index) => (index + 2) % 4;

int playerIndexById(final GameEngineState state, final String playerId) => state.players.indexWhere((final player) => player.id == playerId);

List<String> opponentIdsForPlayer(final GameEngineState state, final String playerId) {
  final player = state.players.firstWhere((final p) => p.id == playerId);
  return state.players
      .where((final p) => p.id != playerId && (p.seat % 2 != player.seat % 2))
      .map((final p) => p.id)
      .toList();
}
