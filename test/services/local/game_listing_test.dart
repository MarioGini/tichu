import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_session.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/services/local/local_table_service.dart';

void main() {
  group('Game listing', () {
    late LocalGameTableService service;

    setUp(() {
      service = LocalGameTableService();
    });

    test('returns assembling lobbies of all visibility types', () async {
      await service.createLobby(
        const CreateGameLobbyRequest(
          displayName: 'Host A',
          gameName: 'Fun Game',
          visibility: GameLobbyVisibility.public,
        ),
      );
      await service.createLobby(
        const CreateGameLobbyRequest(
          displayName: 'Host B',
          gameName: 'Secret Game',
          visibility: GameLobbyVisibility.private,
        ),
      );

      final games = await service.listGames();
      expect(games, hasLength(2));

      final publicGame = games.firstWhere(
        (final g) => g.visibility == GameLobbyVisibility.public,
      );
      expect(publicGame.gameName, 'Fun Game');
      expect(publicGame.hostDisplayName, 'Host A');
      expect(publicGame.occupiedSeats, 0);
      expect(publicGame.totalSeats, 4);

      final privateGame = games.firstWhere(
        (final g) => g.visibility == GameLobbyVisibility.private,
      );
      expect(privateGame.gameName, 'Secret Game');
    });

    test('excludes active and finished lobbies', () async {
      final handle = await service.createLobby(
        const CreateGameLobbyRequest(
          displayName: 'Host',
          gameName: 'Will Start',
          preferredTeam: 0,
        ),
      );
      await service.setReadyState(
        handle.lobbyId,
        accessToken: handle.accessToken,
        isReady: true,
      );
      for (var seat = 0; seat < 4; seat++) {
        final lobby = await service
            .watchLobby(handle.lobbyId, accessToken: handle.accessToken)
            .first;
        if (lobby.seats[seat].state == GameLobbySeatState.open) {
          await service.claimSeat(
            handle.lobbyId,
            accessToken: handle.accessToken,
            seat: seat,
            type: PlayerType.automated,
            automatedDisplayName: 'Bot ${seat + 1}',
          );
        }
      }
      await service.startMatch(handle.lobbyId, accessToken: handle.accessToken);

      final games = await service.listGames();
      expect(games, isEmpty);
    });

    test('joining by lobbyId works for public games', () async {
      final hostHandle = await service.createLobby(
        const CreateGameLobbyRequest(
          displayName: 'Host',
          gameName: 'Open Game',
          visibility: GameLobbyVisibility.public,
        ),
      );

      final joinHandle = await service.joinLobby(
        JoinGameLobbyRequest(
          joinCode: hostHandle.lobbyId,
          displayName: 'Joiner',
        ),
      );

      expect(joinHandle.lobbyId, hostHandle.lobbyId);
    });

    test('reports occupied seat count correctly', () async {
      final handle = await service.createLobby(
        const CreateGameLobbyRequest(
          displayName: 'Host',
          gameName: 'Filling Up',
          preferredTeam: 0,
        ),
      );
      await service.claimSeat(
        handle.lobbyId,
        accessToken: handle.accessToken,
        seat: 1,
        type: PlayerType.automated,
        automatedDisplayName: 'Bot',
      );

      final games = await service.listGames();
      final game = games.single;
      expect(game.occupiedSeats, 2);
    });
  });
}
