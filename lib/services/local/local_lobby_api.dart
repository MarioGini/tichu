part of 'local_table_service.dart';

/// Lobby listing, seats, ready state and match start.
mixin _LocalLobbyApi on _LocalTableBase implements GameSessionService {
  @override
  Future<List<GameLobbyListEntry>> listGames() async => <GameLobbyListEntry>[
    for (final lobby in _lobbies.values)
      if (lobby.state == GameLobbyState.assembling ||
          lobby.state == GameLobbyState.readyCheck)
        GameLobbyListEntry(
          lobbyId: lobby.lobbyId,
          gameName: lobby.gameName,
          hostDisplayName: _hostDisplayName(lobby),
          targetScore: lobby.targetScore,
          visibility: lobby.visibility,
          occupiedSeats: lobby.seats
              .where((s) => s.state == GameLobbySeatState.occupied)
              .length,
        ),
  ];

  String _hostDisplayName(_LocalLobbyState lobby) {
    final host = lobby.participantsByPlayerId[lobby.hostPlayerId];
    return host?.displayName ?? 'Unknown';
  }

  @override
  Stream<GameLobbySnapshot> watchLobby(
    String lobbyId, {
    required String accessToken,
  }) async* {
    final lobby = _requireLobby(lobbyId);
    final participant = _requireParticipant(lobby, accessToken);
    yield _roundTripLobbySnapshot(
      _buildLobbySnapshot(lobby, participant.playerId),
    );
    yield* lobby.lobbyEvents.stream.map(
      (_) => _roundTripLobbySnapshot(
        _buildLobbySnapshot(lobby, participant.playerId),
      ),
    );
  }

  @override
  Future<void> claimSeat(
    String lobbyId, {
    required String accessToken,
    required int seat,
    PlayerType type = PlayerType.human,
    String? automatedDisplayName,
  }) async {
    final lobby = _requireLobby(lobbyId);
    final participant = _requireParticipant(lobby, accessToken);
    _ensureSeatIndex(lobby, seat);
    _ensureLobbyNotActive(lobby);

    if (type == PlayerType.automated && automatedDisplayName != null) {
      _claimAutomatedSeat(lobby, seat, automatedDisplayName);
      _emitLobby(lobby);
      return;
    }

    _claimParticipantSeat(lobby, participant, seat: seat, type: type);
    _emitLobby(lobby);
  }

  @override
  Future<void> setReadyState(
    String lobbyId, {
    required String accessToken,
    required bool isReady,
  }) async {
    final lobby = _requireLobby(lobbyId);
    final participant = _requireParticipant(lobby, accessToken);
    participant.isReady = isReady;
    final seat = participant.seat;
    if (seat != null) {
      final seatState = lobby.seats[seat];
      if (seatState.playerId == participant.playerId) {
        seatState.isReady = isReady;
      }
    }
    _emitLobby(lobby);
  }

  @override
  Future<void> startMatch(String lobbyId, {required String accessToken}) async {
    final lobby = _requireLobby(lobbyId);
    final participant = _requireParticipant(lobby, accessToken);
    if (participant.playerId != lobby.hostPlayerId) {
      throw const RequestRejectedException(
        'Only the host can start the match.',
      );
    }
    if (!_canStart(lobby)) {
      throw const RequestRejectedException(
        'All seats must be occupied and ready before starting.',
      );
    }
    if (lobby.runtime != null || lobby.matchId != null) {
      throw const RequestRejectedException(
        'Match already started for this lobby.',
      );
    }

    final runtime = _runtimeFactory();
    final players = [
      for (final seatState in lobby.seats)
        GamePlayer(
          id: seatState.playerId!,
          name: seatState.displayName!,
          seat: seatState.seat,
          type: seatState.type,
        ),
    ];
    final matchId = await runtime.createGame(
      players,
      targetScore: lobby.targetScore,
    );

    lobby.runtime = runtime;
    lobby.matchId = matchId;
    lobby.state = GameLobbyState.active;
    lobby.runtimeSubscription = runtime
        .watchGameState(matchId)
        .listen((snapshot) => _handleBackendSnapshot(lobby, snapshot));
    await runtime.setAutomatedActionDelay(lobby.automatedActionDelay);
    _emitLobby(lobby);
    _emitConnection(
      lobby,
      const GameMatchConnectionSnapshot(state: GameMatchConnectionState.live),
    );
    await runtime.startGame(matchId);
  }
}
