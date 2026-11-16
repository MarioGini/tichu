part of 'supabase_multiplayer_backend.dart';

final class SupabaseGameMatchService extends _SupabaseServiceBase
    implements GameMatchService {
  SupabaseGameMatchService({required super.client, required super.config});

  @override
  Stream<GameMatchView> watchMatch(
    final String matchId, {
    required final String accessToken,
  }) => withHeartbeat(
    heartbeatBody: <String, dynamic>{
      'matchId': matchId,
      'accessToken': accessToken,
    },
    source: () => _watchMatchProjected(matchId, accessToken: accessToken),
  );

  Stream<GameMatchView> _watchMatchProjected(
    final String matchId, {
    required final String accessToken,
  }) => watchProjectedValue(
    channelTopic: 'tichu:match:$matchId:$accessToken',
    table: _SupabaseServiceBase._matchViewTable,
    scopeColumn: 'match_id',
    scopeValue: matchId,
    loadProjectedValue: () async {
      final payload = await loadProjectedPayload(
        table: _SupabaseServiceBase._matchViewTable,
        scopeColumn: 'match_id',
        scopeValue: matchId,
        accessToken: accessToken,
      );
      if (payload == null) {
        return null;
      }
      return match_dto.GameMatchViewDto.fromJson(payload).toDomain();
    },
    loadFallbackValue: () async {
      final payload = await invokeJson(
        'get-match-view',
        body: <String, dynamic>{'matchId': matchId, 'accessToken': accessToken},
      );
      return match_dto.GameMatchViewDto.fromJson(payload).toDomain();
    },
    signatureOf: (final value) =>
        jsonEncode(match_dto.GameMatchViewDto.fromDomain(value).toJson()),
  );

  @override
  Stream<GameMatchConnectionSnapshot> watchConnection(
    final String matchId, {
    required final String accessToken,
  }) => watchProjectedValue(
    channelTopic: 'tichu:connection:$matchId:$accessToken',
    table: _SupabaseServiceBase._connectionViewTable,
    scopeColumn: 'match_id',
    scopeValue: matchId,
    seedValue: const GameMatchConnectionSnapshot(
      state: GameMatchConnectionState.connecting,
    ),
    loadProjectedValue: () async {
      final payload = await loadProjectedPayload(
        table: _SupabaseServiceBase._connectionViewTable,
        scopeColumn: 'match_id',
        scopeValue: matchId,
        accessToken: accessToken,
      );
      if (payload == null) {
        return null;
      }
      return match_dto.GameMatchConnectionSnapshotDto.fromJson(
        payload,
      ).toDomain();
    },
    loadFallbackValue: () async {
      final payload = await invokeJson(
        'get-match-connection',
        body: <String, dynamic>{'matchId': matchId, 'accessToken': accessToken},
      );
      return match_dto.GameMatchConnectionSnapshotDto.fromJson(
        payload,
      ).toDomain();
    },
    signatureOf: (final value) => jsonEncode(
      match_dto.GameMatchConnectionSnapshotDto.fromDomain(value).toJson(),
    ),
    onStatus: (final controller, final status, final error) {
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        controller.add(
          GameMatchConnectionSnapshot(
            state: GameMatchConnectionState.reconnecting,
            detail: error?.toString(),
            updatedAt: DateTime.now(),
          ),
        );
      }
    },
    onProjectionMiss: (final controller) async {
      controller.add(
        GameMatchConnectionSnapshot(
          state: GameMatchConnectionState.closed,
          updatedAt: DateTime.now(),
        ),
      );
    },
  );

  @override
  Future<void> submitAction(
    final String matchId,
    final GameActionSubmission submission, {
    required final String accessToken,
  }) => invokeVoid(
    'submit-action',
    body: <String, dynamic>{
      'matchId': matchId,
      'accessToken': accessToken,
      'submission': match_dto.GameActionSubmissionDto.fromDomain(
        submission,
      ).toJson(),
    },
  );

  @override
  Future<void> acknowledgeRoundSummary(
    final String matchId,
    final RoundSummaryAcknowledgement acknowledgement, {
    required final String accessToken,
  }) => invokeVoid(
    'acknowledge-round-summary',
    body: <String, dynamic>{
      'matchId': matchId,
      'accessToken': accessToken,
      'acknowledgement': match_dto.RoundSummaryAcknowledgementDto.fromDomain(
        acknowledgement,
      ).toJson(),
    },
  );

  @override
  Future<void> leaveMatch(
    final String matchId, {
    required final String accessToken,
  }) => invokeVoid(
    'leave-match',
    body: <String, dynamic>{'matchId': matchId, 'accessToken': accessToken},
  );
}
