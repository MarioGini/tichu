part of 'local_table_service.dart';

/// Publishing state to watchers, projection and state stores, plus the JSON
/// round trips that keep the local service honest about the wire format.
extension _PublishHelpers on _LocalTableBase {
  void _handleBackendSnapshot(
    final _LocalLobbyState lobby,
    final GameSnapshot snapshot,
  ) {
    if (snapshot.scoreState.gameComplete) {
      lobby.state = GameLobbyState.finished;
      lobby.pendingRoundNumber = null;
      lobby.pendingAcknowledgementPlayerIds.clear();
      _emitLobby(lobby);
      _publishMatchState(lobby, snapshot);
      return;
    }

    if (snapshot.scoreState.roundComplete) {
      final roundNumber = snapshot.scoreState.roundNumber;
      if (lobby.pendingRoundNumber != roundNumber) {
        lobby.pendingRoundNumber = roundNumber;
        lobby.pendingAcknowledgementPlayerIds
          ..clear()
          ..addAll(lobby.participantsByPlayerId.keys);
      }
    } else {
      lobby.pendingRoundNumber = null;
      lobby.pendingAcknowledgementPlayerIds.clear();
    }

    _publishMatchState(lobby, snapshot);
  }

  void _publishMatchState(
    final _LocalLobbyState lobby,
    final GameSnapshot snapshot,
  ) {
    final matchId = lobby.matchId;
    if (matchId == null) {
      throw StateError('Cannot publish match state without a matchId.');
    }

    final event = _LocalMatchState(
      matchId: matchId,
      snapshot: snapshot,
      revision: ++lobby.revision,
      roundAcknowledgementRequired:
          lobby.pendingAcknowledgementPlayerIds.isNotEmpty,
    );
    lobby.latestMatchState = event;
    lobby.matchEvents.add(event);
    unawaited(
      _projectionStore.replaceMatchViews(matchId, [
        for (final participant in lobby.participantsByPlayerId.values)
          _buildProjectedMatchView(lobby, participant, event),
      ]),
    );
  }

  GameLobbySnapshot _buildLobbySnapshot(
    final _LocalLobbyState lobby,
    final String localPlayerId,
  ) => GameLobbySnapshot(
    lobbyId: lobby.lobbyId,
    joinCode: lobby.joinCode,
    localPlayerId: localPlayerId,
    hostPlayerId: lobby.hostPlayerId,
    matchId: lobby.matchId,
    gameName: lobby.gameName,
    targetScore: lobby.targetScore,
    state: lobby.state,
    visibility: lobby.visibility,
    canStart: _canStart(lobby),
    isLocalPlayerHost: localPlayerId == lobby.hostPlayerId,
    seats: [for (final seat in lobby.seats) seat.toSnapshot()],
  );

  GameMatchView _buildMatchView(
    final _LocalLobbyState lobby,
    final _LocalParticipant participant,
    final _LocalMatchState event,
  ) {
    final snapshot = _projectionEngine.buildPlayerSnapshot(
      event.snapshot,
      participant.playerId,
    );
    final selfSeat =
        participant.seat ??
        snapshot.players
            .firstWhere((final player) => player.id == participant.playerId)
            .seat;
    return GameMatchView(
      lobbyId: lobby.lobbyId,
      matchId: event.matchId,
      selfPlayerId: participant.playerId,
      selfSeat: selfSeat,
      revision: event.revision,
      roundAcknowledgementRequired: event.roundAcknowledgementRequired,
      snapshot: snapshot,
    );
  }

  CreateGameLobbyRequest _roundTripCreateLobbyRequest(
    final CreateGameLobbyRequest request,
  ) => session_dto.CreateGameLobbyRequestDto.fromJson(
    _roundTripJson(
      session_dto.CreateGameLobbyRequestDto.fromDomain(request).toJson(),
    ),
  ).toDomain();

  JoinGameLobbyRequest _roundTripJoinLobbyRequest(
    final JoinGameLobbyRequest request,
  ) => session_dto.JoinGameLobbyRequestDto.fromJson(
    _roundTripJson(
      session_dto.JoinGameLobbyRequestDto.fromDomain(request).toJson(),
    ),
  ).toDomain();

  GameSessionHandle _roundTripSessionHandle(final GameSessionHandle handle) =>
      session_dto.GameSessionHandleDto.fromJson(
        _roundTripJson(
          session_dto.GameSessionHandleDto.fromDomain(handle).toJson(),
        ),
      ).toDomain();

  GameLobbySnapshot _roundTripLobbySnapshot(final GameLobbySnapshot snapshot) =>
      session_dto.GameLobbySnapshotDto.fromJson(
        _roundTripJson(
          session_dto.GameLobbySnapshotDto.fromDomain(snapshot).toJson(),
        ),
      ).toDomain();

  GameMatchConnectionSnapshot _roundTripConnectionSnapshot(
    final GameMatchConnectionSnapshot snapshot,
  ) => match_dto.GameMatchConnectionSnapshotDto.fromJson(
    _roundTripJson(
      match_dto.GameMatchConnectionSnapshotDto.fromDomain(snapshot).toJson(),
    ),
  ).toDomain();

  GameMatchView _roundTripMatchView(final GameMatchView view) =>
      match_dto.GameMatchViewDto.fromJson(
        _roundTripJson(match_dto.GameMatchViewDto.fromDomain(view).toJson()),
      ).toDomain();

  GameActionSubmission _roundTripSubmission(
    final GameActionSubmission submission,
  ) => match_dto.GameActionSubmissionDto.fromJson(
    _roundTripJson(
      match_dto.GameActionSubmissionDto.fromDomain(submission).toJson(),
    ),
  ).toDomain();

  RoundSummaryAcknowledgement _roundTripAcknowledgement(
    final RoundSummaryAcknowledgement acknowledgement,
  ) => match_dto.RoundSummaryAcknowledgementDto.fromJson(
    _roundTripJson(
      match_dto.RoundSummaryAcknowledgementDto.fromDomain(
        acknowledgement,
      ).toJson(),
    ),
  ).toDomain();

  Map<String, dynamic> _roundTripJson(final Map<String, dynamic> json) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(json)) as Map);

  void _emitLobby(final _LocalLobbyState lobby) {
    if (!lobby.lobbyEvents.isClosed) {
      lobby.lobbyEvents.add(null);
    }
    unawaited(
      _projectionStore.replaceLobbyViews(lobby.lobbyId, [
        for (final participant in lobby.participantsByPlayerId.values)
          _buildProjectedLobbyView(lobby, participant),
      ]),
    );
    unawaited(
      _stateStore.saveLobbyState(lobby.lobbyId, _serializeLobby(lobby)),
    );
  }

  void _emitConnection(
    final _LocalLobbyState lobby,
    final GameMatchConnectionSnapshot snapshot,
  ) {
    lobby.lastConnectionSnapshot = snapshot;
    if (!lobby.connectionEvents.isClosed) {
      lobby.connectionEvents.add(snapshot);
    }

    final matchId = lobby.matchId;
    if (matchId != null) {
      unawaited(
        _projectionStore.replaceConnectionViews(matchId, [
          for (final participant in lobby.participantsByPlayerId.values)
            _buildProjectedConnectionView(lobby, participant, snapshot),
        ]),
      );
    }
  }

  ProjectedLobbyView _buildProjectedLobbyView(
    final _LocalLobbyState lobby,
    final _LocalParticipant participant,
  ) => ProjectedLobbyView(
    lobbyId: lobby.lobbyId,
    authUserId: participant.authUserId,
    accessToken: participant.accessToken,
    playerId: participant.playerId,
    payload: session_dto.GameLobbySnapshotDto.fromDomain(
      _buildLobbySnapshot(lobby, participant.playerId),
    ).toJson(),
  );

  ProjectedMatchView _buildProjectedMatchView(
    final _LocalLobbyState lobby,
    final _LocalParticipant participant,
    final _LocalMatchState event,
  ) {
    final view = _buildMatchView(lobby, participant, event);
    return ProjectedMatchView(
      lobbyId: lobby.lobbyId,
      matchId: event.matchId,
      authUserId: participant.authUserId,
      accessToken: participant.accessToken,
      playerId: participant.playerId,
      revision: event.revision,
      payload: match_dto.GameMatchViewDto.fromDomain(view).toJson(),
    );
  }

  ProjectedConnectionView _buildProjectedConnectionView(
    final _LocalLobbyState lobby,
    final _LocalParticipant participant,
    final GameMatchConnectionSnapshot snapshot,
  ) => ProjectedConnectionView(
    lobbyId: lobby.lobbyId,
    matchId: lobby.matchId!,
    authUserId: participant.authUserId,
    accessToken: participant.accessToken,
    playerId: participant.playerId,
    payload: match_dto.GameMatchConnectionSnapshotDto.fromDomain(
      snapshot,
    ).toJson(),
  );

  Map<String, dynamic> _serializeLobby(final _LocalLobbyState lobby) =>
      <String, dynamic>{
        'lobbyId': lobby.lobbyId,
        'joinCode': lobby.joinCode,
        'hostPlayerId': lobby.hostPlayerId,
        'gameName': lobby.gameName,
        'targetScore': lobby.targetScore,
        'visibility': lobby.visibility.name,
        'state': lobby.state.name,
        'matchId': lobby.matchId,
        'revision': lobby.revision,
        'pendingRoundNumber': lobby.pendingRoundNumber,
        'pendingAcknowledgementPlayerIds': lobby.pendingAcknowledgementPlayerIds
            .toList(),
        'participants': <Map<String, dynamic>>[
          for (final p in lobby.participantsByPlayerId.values)
            <String, dynamic>{
              'playerId': p.playerId,
              'authUserId': p.authUserId,
              'accessToken': p.accessToken,
              'displayName': p.displayName,
              'seat': p.seat,
              'isReady': p.isReady,
              'isConnected': p.isConnected,
            },
        ],
        'seats': <Map<String, dynamic>>[
          for (final s in lobby.seats)
            <String, dynamic>{
              'seat': s.seat,
              'state': s.state.name,
              'type': s.type.name,
              'playerId': s.playerId,
              'displayName': s.displayName,
              'isReady': s.isReady,
              'isConnected': s.isConnected,
              'isBot': s.isBot,
            },
        ],
      };
}
