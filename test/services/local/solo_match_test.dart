import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_session.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/services/multiplayer/multiplayer_backend.dart';
import 'package:tichu/services/multiplayer/solo_match.dart';

void main() {
  test('startSoloMatch seats the player with three bots and starts', () async {
    final backend = LocalMultiplayerBackend();

    final handle = await startSoloMatch(backend, displayName: 'Mario');

    expect(handle.matchId, isNotNull);
    expect(handle.seat, isNotNull);

    final lobby = await backend.sessionService
        .watchLobby(handle.lobbyId, accessToken: handle.accessToken)
        .first;
    expect(lobby.state, GameLobbyState.active);
    final human = lobby.seats.where((s) => s.type == PlayerType.human);
    final bots = lobby.seats.where((s) => s.type == PlayerType.automated);
    expect(human.single.playerId, handle.playerId);
    expect(human.single.seat, handle.seat);
    expect(bots, hasLength(3));
  });
}
