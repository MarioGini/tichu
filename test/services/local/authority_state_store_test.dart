import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_session.dart';
import 'package:tichu/services/local/local_table_service.dart';
import 'package:tichu/services/multiplayer/authority_state_store.dart';

void main() {
  group('NoopAuthorityStateStore', () {
    test('all methods complete without error', () async {
      const store = NoopAuthorityStateStore();
      await store.saveLobbyState('lobby-1', <String, dynamic>{'key': 'value'});
      final lobbies = await store.loadAllLobbyStates();
      expect(lobbies, isEmpty);
      await store.deleteLobbyState('lobby-1');
      await store.appendAction('match-1', 'lobby-1', <String, dynamic>{
        'action': 'pass',
      });
      final actions = await store.loadActions('match-1');
      expect(actions, isEmpty);
    });
  });

  group('Lobby state persistence', () {
    test('saveLobbyState is called with expected shape on create', () async {
      final store = _RecordingStateStore();
      final service = LocalGameTableService(stateStore: store);

      final handle = await service.createLobby(
        const CreateGameLobbyRequest(
          displayName: 'Host',
          targetScore: 500,
          preferredTeam: 0,
        ),
      );

      expect(store.savedLobbies, isNotEmpty);
      final savedState = store.savedLobbies[handle.lobbyId];
      expect(savedState, isNotNull);
      expect(savedState!['lobbyId'], handle.lobbyId);
      expect(savedState['targetScore'], 500);
      expect(savedState['hostPlayerId'], handle.playerId);
      expect(savedState['state'], 'assembling');
      expect(savedState['participants'], isA<List<dynamic>>());
      expect(savedState['seats'], isA<List<dynamic>>());

      final participants =
          savedState['participants'] as List<Map<String, dynamic>>;
      expect(participants, hasLength(1));
      expect(participants.first['playerId'], handle.playerId);
      expect(participants.first['accessToken'], handle.accessToken);
      expect(participants.first['seat'], 0);
    });

    test('deleteLobbyState is called when lobby closes', () async {
      final store = _RecordingStateStore();
      final service = LocalGameTableService(stateStore: store);

      final handle = await service.createLobby(
        const CreateGameLobbyRequest(displayName: 'Host', preferredTeam: 0),
      );

      await service.leaveLobby(handle.lobbyId, accessToken: handle.accessToken);

      expect(store.deletedLobbyIds, contains(handle.lobbyId));
    });
  });
}

class _RecordingStateStore implements AuthorityStateStore {
  final Map<String, Map<String, dynamic>> savedLobbies =
      <String, Map<String, dynamic>>{};
  final List<String> deletedLobbyIds = <String>[];
  final List<Map<String, dynamic>> appendedActions = <Map<String, dynamic>>[];

  @override
  Future<void> saveLobbyState(
    final String lobbyId,
    final Map<String, dynamic> state,
  ) async {
    savedLobbies[lobbyId] = state;
  }

  @override
  Future<Map<String, Map<String, dynamic>>> loadAllLobbyStates() async =>
      Map<String, Map<String, dynamic>>.from(savedLobbies);

  @override
  Future<void> deleteLobbyState(final String lobbyId) async {
    savedLobbies.remove(lobbyId);
    deletedLobbyIds.add(lobbyId);
  }

  @override
  Future<void> appendAction(
    final String matchId,
    final String lobbyId,
    final Map<String, dynamic> action,
  ) async {
    appendedActions.add(action);
  }

  @override
  Future<List<Map<String, dynamic>>> loadActions(final String matchId) async =>
      List<Map<String, dynamic>>.from(appendedActions);
}
