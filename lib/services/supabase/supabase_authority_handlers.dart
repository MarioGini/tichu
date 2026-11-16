part of 'supabase_authority_server.dart';

/// One handler per Edge Function action; see [SupabaseAuthorityServer].
extension _AuthorityHandlers on SupabaseAuthorityServer {
  Future<Map<String, dynamic>> _createLobby(
    final Map<String, dynamic> body, {
    final String? authUserId,
  }) async {
    final resolvedAuthUserId = _requireAuthUserId(authUserId);
    final request = session_dto.CreateGameLobbyRequestDto.fromJson(
      _requireMap(body, 'request'),
    ).toDomain();
    final handle = await _tableService.createLobbyForAuthUser(
      request,
      authUserId: resolvedAuthUserId,
    );
    return session_dto.GameSessionHandleDto.fromDomain(handle).toJson();
  }

  Future<Map<String, dynamic>> _joinLobby(
    final Map<String, dynamic> body, {
    final String? authUserId,
  }) async {
    final resolvedAuthUserId = _requireAuthUserId(authUserId);
    final request = session_dto.JoinGameLobbyRequestDto.fromJson(
      _requireMap(body, 'request'),
    ).toDomain();
    final handle = await _tableService.joinLobbyForAuthUser(
      request,
      authUserId: resolvedAuthUserId,
    );
    return session_dto.GameSessionHandleDto.fromDomain(handle).toJson();
  }

  Future<Map<String, dynamic>> _listGames() async {
    final entries = await _tableService.listGames();
    return <String, dynamic>{
      'games': <Map<String, dynamic>>[
        for (final entry in entries)
          session_dto.GameLobbyListEntryDto.fromDomain(entry).toJson(),
      ],
    };
  }

  Future<Map<String, dynamic>> _getLobby(
    final Map<String, dynamic> body,
  ) async {
    final snapshot = await _tableService
        .watchLobby(
          _requireString(body, 'lobbyId'),
          accessToken: _requireString(body, 'accessToken'),
        )
        .first;
    return session_dto.GameLobbySnapshotDto.fromDomain(snapshot).toJson();
  }

  Future<void> _claimSeat(final Map<String, dynamic> body) {
    final typeName = (body['type'] as String?) ?? PlayerType.human.name;
    return _tableService.claimSeat(
      _requireString(body, 'lobbyId'),
      accessToken: _requireString(body, 'accessToken'),
      seat: _requireInt(body, 'seat'),
      type: PlayerType.values.byName(typeName),
      automatedDisplayName: body['automatedDisplayName'] as String?,
    );
  }

  Future<void> _setReadyState(final Map<String, dynamic> body) =>
      _tableService.setReadyState(
        _requireString(body, 'lobbyId'),
        accessToken: _requireString(body, 'accessToken'),
        isReady: _requireBool(body, 'isReady'),
      );

  Future<void> _startMatch(final Map<String, dynamic> body) =>
      _tableService.startMatch(
        _requireString(body, 'lobbyId'),
        accessToken: _requireString(body, 'accessToken'),
      );

  Future<void> _leaveLobby(final Map<String, dynamic> body) =>
      _tableService.leaveLobby(
        _requireString(body, 'lobbyId'),
        accessToken: _requireString(body, 'accessToken'),
      );

  Future<Map<String, dynamic>> _getMatchView(
    final Map<String, dynamic> body,
  ) async {
    final view = await _tableService
        .watchMatch(
          _requireString(body, 'matchId'),
          accessToken: _requireString(body, 'accessToken'),
        )
        .first;
    return match_dto.GameMatchViewDto.fromDomain(view).toJson();
  }

  Future<Map<String, dynamic>> _getMatchConnection(
    final Map<String, dynamic> body,
  ) async {
    final snapshot = await _tableService
        .watchConnection(
          _requireString(body, 'matchId'),
          accessToken: _requireString(body, 'accessToken'),
        )
        .first;
    return match_dto.GameMatchConnectionSnapshotDto.fromDomain(
      snapshot,
    ).toJson();
  }

  Future<void> _submitAction(final Map<String, dynamic> body) {
    final submission = match_dto.GameActionSubmissionDto.fromJson(
      _requireMap(body, 'submission'),
    ).toDomain();
    return _tableService.submitAction(
      _requireString(body, 'matchId'),
      submission,
      accessToken: _requireString(body, 'accessToken'),
    );
  }

  Future<void> _acknowledgeRoundSummary(final Map<String, dynamic> body) {
    final acknowledgement = match_dto.RoundSummaryAcknowledgementDto.fromJson(
      _requireMap(body, 'acknowledgement'),
    ).toDomain();
    return _tableService.acknowledgeRoundSummary(
      _requireString(body, 'matchId'),
      acknowledgement,
      accessToken: _requireString(body, 'accessToken'),
    );
  }

  Future<void> _leaveMatch(final Map<String, dynamic> body) =>
      _tableService.leaveMatch(
        _requireString(body, 'matchId'),
        accessToken: _requireString(body, 'accessToken'),
      );

  Future<void> _heartbeat(final Map<String, dynamic> body) {
    final accessToken = _requireString(body, 'accessToken');
    final lobbyId = body['lobbyId'] as String?;
    final matchId = body['matchId'] as String?;
    if (matchId != null && matchId.isNotEmpty) {
      return _tableService.sendMatchHeartbeat(
        matchId,
        accessToken: accessToken,
      );
    }
    if (lobbyId != null && lobbyId.isNotEmpty) {
      return _tableService.sendHeartbeat(lobbyId, accessToken: accessToken);
    }
    throw const _ClientRequestError(
      HttpStatus.badRequest,
      'heartbeat requires lobbyId or matchId.',
    );
  }
}
