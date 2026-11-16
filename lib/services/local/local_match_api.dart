part of 'local_table_service.dart';

/// [GameMatchService] side of [LocalGameTableService].
mixin _LocalMatchApi on _LocalTableBase
    implements GameMatchService, AdjustableAutomatedActionDelay {
  @override
  Stream<GameMatchView> watchMatch(
    final String matchId, {
    required final String accessToken,
  }) async* {
    final resolved = _requireActiveMatch(matchId, accessToken);
    final current = resolved.lobby.latestMatchState;
    if (current != null) {
      yield _roundTripMatchView(
        _buildMatchView(resolved.lobby, resolved.participant, current),
      );
    }
    yield* resolved.lobby.matchEvents.stream.map(
      (final event) => _roundTripMatchView(
        _buildMatchView(resolved.lobby, resolved.participant, event),
      ),
    );
  }

  @override
  Stream<GameMatchConnectionSnapshot> watchConnection(
    final String matchId, {
    required final String accessToken,
  }) async* {
    final resolved = _requireActiveMatch(matchId, accessToken);
    final current = resolved.lobby.lastConnectionSnapshot;
    if (current != null) {
      yield _roundTripConnectionSnapshot(current);
    }
    yield* resolved.lobby.connectionEvents.stream.map(
      _roundTripConnectionSnapshot,
    );
  }

  @override
  Future<void> submitAction(
    final String matchId,
    final GameActionSubmission submission, {
    required final String accessToken,
  }) async {
    final decodedSubmission = _roundTripSubmission(submission);
    final resolved = _requireActiveMatch(matchId, accessToken);
    final lobby = resolved.lobby;
    if (lobby.processedClientActionIds.contains(
      decodedSubmission.clientActionId,
    )) {
      return;
    }

    final latestRevision = lobby.latestMatchState?.revision;
    if (decodedSubmission.expectedRevision != null &&
        latestRevision != null &&
        latestRevision != decodedSubmission.expectedRevision) {
      throw StateError('Stale match revision. Refresh and retry.');
    }

    await lobby.runtime!.submitAction(matchId, decodedSubmission.action);
    lobby.processedClientActionIds.add(decodedSubmission.clientActionId);
    unawaited(
      _stateStore.appendAction(
        matchId,
        lobby.lobbyId,
        match_dto.GameActionSubmissionDto.fromDomain(
          decodedSubmission,
        ).toJson(),
      ),
    );
  }

  @override
  Future<void> acknowledgeRoundSummary(
    final String matchId,
    final RoundSummaryAcknowledgement acknowledgement, {
    required final String accessToken,
  }) async {
    final decodedAcknowledgement = _roundTripAcknowledgement(acknowledgement);
    final resolved = _requireActiveMatch(matchId, accessToken);
    final lobby = resolved.lobby;
    if (lobby.processedClientActionIds.contains(
      decodedAcknowledgement.clientActionId,
    )) {
      return;
    }

    final latestState = lobby.latestMatchState;
    if (latestState == null) {
      throw StateError('No match snapshot available yet.');
    }
    if (!latestState.roundAcknowledgementRequired) {
      return;
    }
    if (decodedAcknowledgement.expectedRevision != null &&
        decodedAcknowledgement.expectedRevision != latestState.revision) {
      throw StateError('Stale match revision. Refresh and retry.');
    }
    if (lobby.pendingRoundNumber != decodedAcknowledgement.roundNumber) {
      throw StateError(
        'Round acknowledgement does not match the active round.',
      );
    }

    lobby.pendingAcknowledgementPlayerIds.remove(resolved.participant.playerId);
    lobby.processedClientActionIds.add(decodedAcknowledgement.clientActionId);

    if (lobby.pendingAcknowledgementPlayerIds.isEmpty) {
      lobby.pendingRoundNumber = null;
      await lobby.runtime!.startNewRound(matchId);
      return;
    }

    _publishMatchState(lobby, latestState.snapshot);
  }

  @override
  Future<void> leaveMatch(
    final String matchId, {
    required final String accessToken,
  }) async {
    final resolved = _requireActiveMatch(matchId, accessToken);
    final lobby = resolved.lobby;
    final participant = resolved.participant;
    participant.isConnected = false;
    final seat = participant.seat;
    if (seat != null) {
      final seatState = lobby.seats[seat];
      if (seatState.playerId == participant.playerId) {
        seatState.isConnected = false;
      }
    }

    if (lobby.participantsByPlayerId.values.every(
      (final entry) => !entry.isConnected,
    )) {
      await _closeLobby(lobby);
      return;
    }

    _emitLobby(lobby);
  }

  @override
  Future<void> setMatchAutomatedActionDelay(
    final String matchId, {
    required final String accessToken,
    required final Duration delay,
  }) async {
    final resolved = _requireActiveMatch(matchId, accessToken);
    resolved.lobby.automatedActionDelay = delay;
    await resolved.lobby.runtime?.setAutomatedActionDelay(delay);
  }

  Future<void> sendMatchHeartbeat(
    final String matchId, {
    required final String accessToken,
  }) async {
    final resolved = _requireActiveMatch(matchId, accessToken);
    _updateHeartbeat(resolved.lobby, resolved.participant);
  }
}
