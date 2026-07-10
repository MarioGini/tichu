import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_session.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/services/local/local_table_service.dart';

void main() {
  group('Heartbeat presence', () {
    late LocalGameTableService service;

    setUp(() {
      service = LocalGameTableService(
        heartbeatConfig: const HeartbeatConfig(
          timeout: Duration.zero,
          enabled: false,
        ),
      );
    });

    test('sweep marks participant disconnected after timeout', () async {
      final handle = await service.createLobby(
        const CreateGameLobbyRequest(displayName: 'Host', preferredTeam: 0),
      );

      service.sweepHeartbeats();

      final lobby = await service
          .watchLobby(handle.lobbyId, accessToken: handle.accessToken)
          .first;
      final seat = lobby.seats.firstWhere(
        (final s) => s.playerId == handle.playerId,
      );
      expect(seat.isConnected, isFalse);
    });

    test('disconnected participant reconnects on heartbeat', () async {
      final handle = await service.createLobby(
        const CreateGameLobbyRequest(displayName: 'Host', preferredTeam: 0),
      );

      service.sweepHeartbeats();

      await service.sendHeartbeat(
        handle.lobbyId,
        accessToken: handle.accessToken,
      );

      final lobby = await service
          .watchLobby(handle.lobbyId, accessToken: handle.accessToken)
          .first;
      expect(
        lobby.seats
            .firstWhere((final s) => s.playerId == handle.playerId)
            .isConnected,
        isTrue,
      );
    });

    test('bot seats are not affected by sweep', () async {
      final handle = await service.createLobby(
        const CreateGameLobbyRequest(displayName: 'Host', preferredTeam: 0),
      );

      await service.claimSeat(
        handle.lobbyId,
        accessToken: handle.accessToken,
        seat: 1,
        type: PlayerType.automated,
        automatedDisplayName: 'Bot A',
      );

      service.sweepHeartbeats();

      final lobby = await service
          .watchLobby(handle.lobbyId, accessToken: handle.accessToken)
          .first;
      expect(lobby.seats[1].isConnected, isTrue);
    });
  });
}
