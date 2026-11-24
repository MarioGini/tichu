part of 'supabase_multiplayer_backend.dart';

final class SupabaseGameSessionService extends _SupabaseServiceBase
    implements GameSessionService {
  SupabaseGameSessionService({required super.client, required super.config});

  @override
  Future<GameSessionHandle> createLobby(CreateGameLobbyRequest request) async {
    final payload = await invokeJson(
      'create-lobby',
      body: <String, dynamic>{
        'request': session_dto.CreateGameLobbyRequestDto.fromDomain(request)
            .toJson(),
      },
    );
    return session_dto.GameSessionHandleDto.fromJson(payload).toDomain();
  }

  @override
  Future<GameSessionHandle> joinLobby(JoinGameLobbyRequest request) async {
    final payload = await invokeJson(
      'join-lobby',
      body: <String, dynamic>{
        'request': session_dto.JoinGameLobbyRequestDto.fromDomain(request)
            .toJson(),
      },
    );
    return session_dto.GameSessionHandleDto.fromJson(payload).toDomain();
  }

  @override
  Future<List<GameLobbyListEntry>> listGames() async {
    final payload = await invokeJson('list-games');
    final rawList = payload['games'] as List<dynamic>;
    return <GameLobbyListEntry>[
      for (final entry in rawList)
        session_dto.GameLobbyListEntryDto.fromJson(
          Map<String, dynamic>.from(entry as Map),
        ).toDomain(),
    ];
  }

  @override
  Stream<GameLobbySnapshot> watchLobby(
    String lobbyId, {
    required String accessToken,
  }) => withHeartbeat(
    source: () => _watchLobbyProjected(lobbyId, accessToken: accessToken),
    heartbeatBody: <String, dynamic>{
      'lobbyId': lobbyId,
      'accessToken': accessToken,
    },
  );

  Stream<GameLobbySnapshot> _watchLobbyProjected(
    String lobbyId, {
    required String accessToken,
  }) => watchProjectedValue(
    channelTopic: 'tichu:lobby:$lobbyId:$accessToken',
    table: _SupabaseServiceBase._lobbyViewTable,
    scopeColumn: 'lobby_id',
    scopeValue: lobbyId,
    loadProjectedValue: () async {
      final payload = await loadProjectedPayload(
        table: _SupabaseServiceBase._lobbyViewTable,
        scopeColumn: 'lobby_id',
        scopeValue: lobbyId,
        accessToken: accessToken,
      );
      if (payload == null) {
        return null;
      }
      return session_dto.GameLobbySnapshotDto.fromJson(payload).toDomain();
    },
    loadFallbackValue: () async {
      final payload = await invokeJson(
        'get-lobby',
        body: <String, dynamic>{'lobbyId': lobbyId, 'accessToken': accessToken},
      );
      return session_dto.GameLobbySnapshotDto.fromJson(payload).toDomain();
    },
    signatureOf: (value) =>
        jsonEncode(session_dto.GameLobbySnapshotDto.fromDomain(value).toJson()),
  );

  @override
  Future<void> claimSeat(
    String lobbyId, {
    required String accessToken,
    required int seat,
    PlayerType type = PlayerType.human,
    String? automatedDisplayName,
  }) => invokeVoid(
    'claim-seat',
    body: <String, dynamic>{
      'lobbyId': lobbyId,
      'accessToken': accessToken,
      'seat': seat,
      'type': type.name,
      'automatedDisplayName': automatedDisplayName,
    },
  );

  @override
  Future<void> setReadyState(
    String lobbyId, {
    required String accessToken,
    required bool isReady,
  }) => invokeVoid(
    'set-ready-state',
    body: <String, dynamic>{
      'lobbyId': lobbyId,
      'accessToken': accessToken,
      'isReady': isReady,
    },
  );

  @override
  Future<void> startMatch(String lobbyId, {required String accessToken}) =>
      invokeVoid(
        'start-match',
        body: <String, dynamic>{'lobbyId': lobbyId, 'accessToken': accessToken},
      );

  @override
  Future<void> leaveLobby(String lobbyId, {required String accessToken}) =>
      invokeVoid(
        'leave-lobby',
        body: <String, dynamic>{'lobbyId': lobbyId, 'accessToken': accessToken},
      );

  @override
  Future<void> sendHeartbeat(String lobbyId, {required String accessToken}) =>
      invokeVoid(
        'heartbeat',
        body: <String, dynamic>{'lobbyId': lobbyId, 'accessToken': accessToken},
      );
}
