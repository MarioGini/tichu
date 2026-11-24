part of 'local_table_service.dart';

/// Lobby, seat and participant bookkeeping.
extension _LobbyHelpers on _LocalTableBase {
  void _updateHeartbeat(_LocalLobbyState lobby, _LocalParticipant participant) {
    participant.lastHeartbeatAt = DateTime.now();
    if (!participant.isConnected) {
      _markParticipantConnected(lobby, participant);
      _emitLobby(lobby);
    }
  }

  _LocalParticipant _createParticipant({
    required String displayName,
    String? authUserId,
  }) {
    final playerId = 'local-player-${_nextPlayerId++}';
    return _LocalParticipant(
      playerId: playerId,
      authUserId: authUserId ?? playerId,
      accessToken: 'local-token-${_nextAccessTokenId++}',
      displayName: displayName,
    );
  }

  String _generateJoinCode() {
    String code;
    do {
      code = (_random.nextInt(90000) + 10000).toString();
    } while (_lobbyIdByJoinCode.containsKey(code));
    return code;
  }

  /// Returns the first open seat on the given team (0 = even seats, 1 = odd).
  int? _firstOpenSeatForTeam(_LocalLobbyState lobby, int team) {
    final teamSeats = team == 0 ? <int>[0, 2] : <int>[1, 3];
    for (final seatIndex in teamSeats) {
      if (lobby.seats[seatIndex].state == GameLobbySeatState.open) {
        return seatIndex;
      }
    }
    return null;
  }

  _LocalParticipant? _findParticipantByAuthUserId(
    _LocalLobbyState lobby,
    String? authUserId,
  ) {
    if (authUserId == null || authUserId.isEmpty) {
      return null;
    }
    for (final participant in lobby.participantsByPlayerId.values) {
      if (participant.authUserId == authUserId) {
        return participant;
      }
    }
    return null;
  }

  void _markParticipantConnected(
    _LocalLobbyState lobby,
    _LocalParticipant participant,
  ) {
    participant.isConnected = true;
    final seat = participant.seat;
    if (seat != null) {
      final seatState = lobby.seats[seat];
      if (seatState.playerId == participant.playerId) {
        seatState.isConnected = true;
      }
    }
  }

  _LocalLobbyState _requireLobby(String lobbyId) {
    final lobby = _lobbies[lobbyId];
    if (lobby == null) {
      throw RequestRejectedException('Unknown lobbyId: $lobbyId');
    }
    return lobby;
  }

  _LocalParticipant _requireParticipant(
    _LocalLobbyState lobby,
    String accessToken,
  ) {
    final participant = lobby.participantsByAccessToken[accessToken];
    if (participant == null) {
      throw RequestRejectedException(
        'Unknown access token for lobby ${lobby.lobbyId}.',
      );
    }
    return participant;
  }

  ({_LocalLobbyState lobby, _LocalParticipant participant}) _requireActiveMatch(
    String matchId,
    String accessToken,
  ) {
    final lobby = _lobbies.values.firstWhere(
      (entry) => entry.matchId == matchId,
      orElse: () => throw RequestRejectedException('Unknown matchId: $matchId'),
    );
    final participant = _requireParticipant(lobby, accessToken);
    if (lobby.runtime == null) {
      throw const RequestRejectedException('Match is not active.');
    }
    return (lobby: lobby, participant: participant);
  }

  void _ensureSeatIndex(_LocalLobbyState lobby, int seat) {
    if (seat < 0 || seat >= lobby.seats.length) {
      throw RangeError.range(seat, 0, lobby.seats.length - 1, 'seat');
    }
  }

  void _ensureLobbyNotActive(_LocalLobbyState lobby) {
    if (lobby.matchId != null || lobby.runtime != null) {
      throw const RequestRejectedException(
        'Cannot change seats after the match has started.',
      );
    }
  }

  void _claimParticipantSeat(
    _LocalLobbyState lobby,
    _LocalParticipant participant, {
    required int seat,
    required PlayerType type,
  }) {
    final targetSeat = lobby.seats[seat];
    if (targetSeat.isOccupiedByDifferentParticipant(participant.playerId)) {
      throw RequestRejectedException('Seat $seat is already occupied.');
    }

    final previousSeat = participant.seat;
    if (previousSeat != null && previousSeat != seat) {
      lobby.seats[previousSeat].clear();
    }

    participant.seat = seat;
    targetSeat.assignParticipant(
      playerId: participant.playerId,
      displayName: participant.displayName,
      type: type,
      isReady: participant.isReady,
      isConnected: participant.isConnected,
    );
  }

  void _claimAutomatedSeat(
    _LocalLobbyState lobby,
    int seat,
    String displayName,
  ) {
    final targetSeat = lobby.seats[seat];
    if (targetSeat.state == GameLobbySeatState.occupied && !targetSeat.isBot) {
      throw RequestRejectedException(
        'Seat $seat is already occupied by a player.',
      );
    }

    targetSeat.assignBot(
      playerId: 'local-bot-${lobby.lobbyId}-$seat',
      displayName: displayName,
    );
  }

  bool _canStart(_LocalLobbyState lobby) {
    final allSeatsOccupied = lobby.seats.every(
      (seat) => seat.state == GameLobbySeatState.occupied,
    );
    final participantsReady = lobby.participantsByPlayerId.values.every(
      (participant) => participant.isReady && participant.seat != null,
    );
    return allSeatsOccupied && participantsReady;
  }

  void _removeParticipantFromLobby(
    _LocalLobbyState lobby,
    _LocalParticipant participant,
  ) {
    final seat = participant.seat;
    if (seat != null) {
      final seatState = lobby.seats[seat];
      if (seatState.playerId == participant.playerId) {
        seatState.clear();
      }
    }
    lobby.participantsByAccessToken.remove(participant.accessToken);
    lobby.participantsByPlayerId.remove(participant.playerId);
  }

  Future<void> _closeLobby(_LocalLobbyState lobby) async {
    _emitConnection(
      lobby,
      const GameMatchConnectionSnapshot(state: GameMatchConnectionState.closed),
    );
    _lobbies.remove(lobby.lobbyId);
    _lobbyIdByJoinCode.remove(lobby.joinCode);
    await _projectionStore.deleteLobbyState(
      lobby.lobbyId,
      matchId: lobby.matchId,
    );
    await _stateStore.deleteLobbyState(lobby.lobbyId);
    await lobby.dispose();
  }
}
