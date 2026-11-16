part of 'local_table_service.dart';

class _LocalLobbyState {
  _LocalLobbyState({
    required this.lobbyId,
    required this.joinCode,
    required this.hostPlayerId,
    required this.gameName,
    required this.targetScore,
    required this.visibility,
    required this.participantsByAccessToken,
    required this.participantsByPlayerId,
    required this.seats,
  });

  final String lobbyId;
  final String joinCode;
  String hostPlayerId;
  final String gameName;
  final int targetScore;
  final GameLobbyVisibility visibility;
  final Map<String, _LocalParticipant> participantsByAccessToken;
  final Map<String, _LocalParticipant> participantsByPlayerId;
  final List<_LocalSeatState> seats;
  final StreamController<void> lobbyEvents = StreamController<void>.broadcast();
  final StreamController<GameMatchConnectionSnapshot> connectionEvents =
      StreamController<GameMatchConnectionSnapshot>.broadcast();
  final StreamController<_LocalMatchState> matchEvents =
      StreamController<_LocalMatchState>.broadcast();

  GameLobbyState state = GameLobbyState.assembling;
  String? matchId;
  LocalMatchRuntime? runtime;
  StreamSubscription<GameSnapshot>? runtimeSubscription;
  GameMatchConnectionSnapshot? lastConnectionSnapshot =
      const GameMatchConnectionSnapshot(
        state: GameMatchConnectionState.connecting,
      );
  _LocalMatchState? latestMatchState;
  final Set<String> processedClientActionIds = <String>{};
  final Set<String> pendingAcknowledgementPlayerIds = <String>{};
  Duration automatedActionDelay = const Duration(seconds: 1);
  int revision = 0;
  int? pendingRoundNumber;

  Future<void> dispose() async {
    await runtimeSubscription?.cancel();
    runtimeSubscription = null;

    final activeMatchId = matchId;
    if (activeMatchId != null) {
      await runtime?.disposeGame(activeMatchId);
    }

    await lobbyEvents.close();
    await connectionEvents.close();
    await matchEvents.close();
  }
}

class _LocalParticipant {
  _LocalParticipant({
    required this.playerId,
    required this.authUserId,
    required this.accessToken,
    required this.displayName,
  });

  final String playerId;
  final String authUserId;
  final String accessToken;
  final String displayName;
  int? seat;
  bool isReady = false;
  bool isConnected = true;
  DateTime lastHeartbeatAt = DateTime.now();
}

class _LocalSeatState {
  _LocalSeatState({required this.seat});

  final int seat;
  GameLobbySeatState state = GameLobbySeatState.open;
  PlayerType type = PlayerType.human;
  String? playerId;
  String? displayName;
  bool isReady = false;
  bool isConnected = false;
  bool isBot = false;

  bool isOccupiedByDifferentParticipant(final String targetPlayerId) =>
      state == GameLobbySeatState.occupied &&
      playerId != null &&
      playerId != targetPlayerId;

  void assignParticipant({
    required final String playerId,
    required final String displayName,
    required final PlayerType type,
    required final bool isReady,
    required final bool isConnected,
  }) {
    state = GameLobbySeatState.occupied;
    this.playerId = playerId;
    this.displayName = displayName;
    this.type = type;
    this.isReady = isReady;
    this.isConnected = isConnected;
    isBot = false;
  }

  void assignBot({
    required final String playerId,
    required final String displayName,
  }) {
    state = GameLobbySeatState.occupied;
    this.playerId = playerId;
    this.displayName = displayName;
    type = PlayerType.automated;
    isReady = true;
    isConnected = true;
    isBot = true;
  }

  void clear() {
    state = GameLobbySeatState.open;
    type = PlayerType.human;
    playerId = null;
    displayName = null;
    isReady = false;
    isConnected = false;
    isBot = false;
  }

  GameLobbySeatSnapshot toSnapshot() => GameLobbySeatSnapshot(
    seat: seat,
    state: state,
    type: type,
    playerId: playerId,
    displayName: displayName,
    isReady: isReady,
    isConnected: isConnected,
  );
}

class _LocalMatchState {
  const _LocalMatchState({
    required this.matchId,
    required this.snapshot,
    required this.revision,
    required this.roundAcknowledgementRequired,
  });

  final String matchId;
  final GameSnapshot snapshot;
  final int revision;
  final bool roundAcknowledgementRequired;
}
