import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_session.dart';
import 'package:tichu/services/local/local_table_service.dart';
import 'package:tichu/services/multiplayer/table_projection_store.dart';

void main() {
  test('publishes per-player lobby and match projections', () async {
    final projectionStore = _RecordingProjectionStore();
    final service = LocalGameTableService(projectionStore: projectionStore);

    final host = await service.createLobby(
      const CreateGameLobbyRequest(displayName: 'Host', preferredTeam: 0),
    );
    final lobbyAfterHostCreate = projectionStore.lastLobbyViews;
    expect(lobbyAfterHostCreate, hasLength(1));
    expect(lobbyAfterHostCreate.single.accessToken, host.accessToken);
    expect(lobbyAfterHostCreate.single.authUserId, isNotEmpty);

    final joinCode =
        (await service
                .watchLobby(host.lobbyId, accessToken: host.accessToken)
                .first)
            .joinCode!;

    final handles = <GameSessionHandle>[host];
    for (var seat = 1; seat < 4; seat++) {
      final handle = await service.joinLobby(
        JoinGameLobbyRequest(
          joinCode: joinCode,
          displayName: 'Player ${seat + 1}',
        ),
      );
      await service.claimSeat(
        handle.lobbyId,
        accessToken: handle.accessToken,
        seat: seat,
      );
      handles.add(handle);
    }

    expect(projectionStore.lastLobbyViews, hasLength(4));

    for (final handle in handles) {
      await service.setReadyState(
        handle.lobbyId,
        accessToken: handle.accessToken,
        isReady: true,
      );
    }

    await service.startMatch(host.lobbyId, accessToken: host.accessToken);

    expect(projectionStore.lastMatchViews, hasLength(4));
    expect(projectionStore.lastConnectionViews, hasLength(4));

    final accessTokens = {
      for (final view in projectionStore.lastMatchViews) view.accessToken,
    };
    expect(accessTokens, hasLength(4));

    for (final view in projectionStore.lastMatchViews) {
      final snapshot = view.payload['snapshot'];
      expect(snapshot, isA<Map<String, dynamic>>());
      expect((snapshot as Map<String, dynamic>)['hand'], isA<List<dynamic>>());
      expect(view.revision, greaterThan(0));
      expect(view.authUserId, isNotEmpty);
    }

    for (final view in projectionStore.lastConnectionViews) {
      expect(view.payload['state'], 'live');
      expect(view.authUserId, isNotEmpty);
    }
  });
}

class _RecordingProjectionStore implements GameTableProjectionStore {
  List<ProjectedLobbyView> lastLobbyViews = const <ProjectedLobbyView>[];
  List<ProjectedMatchView> lastMatchViews = const <ProjectedMatchView>[];
  List<ProjectedConnectionView> lastConnectionViews =
      const <ProjectedConnectionView>[];
  final List<String> deletedLobbies = <String>[];

  @override
  Future<void> replaceLobbyViews(
    final String lobbyId,
    final List<ProjectedLobbyView> views,
  ) async {
    lastLobbyViews = List<ProjectedLobbyView>.from(views);
  }

  @override
  Future<void> replaceMatchViews(
    final String matchId,
    final List<ProjectedMatchView> views,
  ) async {
    lastMatchViews = List<ProjectedMatchView>.from(views);
  }

  @override
  Future<void> replaceConnectionViews(
    final String matchId,
    final List<ProjectedConnectionView> views,
  ) async {
    lastConnectionViews = List<ProjectedConnectionView>.from(views);
  }

  @override
  Future<void> deleteLobbyState(
    final String lobbyId, {
    final String? matchId,
  }) async {
    deletedLobbies.add(lobbyId);
  }
}
