import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_match.dart';
import 'package:tichu/game/game_session.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';
import 'package:tichu/services/local/local_match_runtime.dart';
import 'package:tichu/services/multiplayer/authority_state_store.dart';
import 'package:tichu/services/multiplayer/table_projection_store.dart';
import 'package:tichu/services/transport/dto/match_dto.dart' as match_dto;
import 'package:tichu/services/transport/dto/session_dto.dart' as session_dto;

class HeartbeatConfig {
  const HeartbeatConfig({
    this.sweepInterval = const Duration(seconds: 10),
    this.timeout = const Duration(seconds: 30),
    this.enabled = false,
  });

  final Duration sweepInterval;
  final Duration timeout;
  final bool enabled;

  static const disabled = HeartbeatConfig();
}

class LocalGameTableService
    implements
        GameSessionService,
        GameMatchService,
        AdjustableAutomatedActionDelay {
  LocalGameTableService({
    final LocalMatchRuntime Function()? runtimeFactory,
    final GameEngine? projectionEngine,
    final GameTableProjectionStore? projectionStore,
    final AuthorityStateStore? stateStore,
    final HeartbeatConfig heartbeatConfig = HeartbeatConfig.disabled,
  }) : _runtimeFactory = runtimeFactory ?? LocalMatchRuntime.new,
       _projectionEngine = projectionEngine ?? GameEngineImpl(),
       _projectionStore =
           projectionStore ?? const NoopGameTableProjectionStore(),
       _stateStore = stateStore ?? const NoopAuthorityStateStore(),
       _heartbeatConfig = heartbeatConfig {
    if (_heartbeatConfig.enabled) {
      _heartbeatSweepTimer = Timer.periodic(
        _heartbeatConfig.sweepInterval,
        (_) => sweepHeartbeats(),
      );
    }
  }

  final LocalMatchRuntime Function() _runtimeFactory;
  final GameEngine _projectionEngine;
  final GameTableProjectionStore _projectionStore;
  final AuthorityStateStore _stateStore;
  final HeartbeatConfig _heartbeatConfig;
  Timer? _heartbeatSweepTimer;
  final Random _random = Random();
  final Map<String, _LocalLobbyState> _lobbies = {};
  final Map<String, String> _lobbyIdByJoinCode = {};
  int _nextLobbyId = 1;
  int _nextPlayerId = 0;
  int _nextAccessTokenId = 1;

  @override
  Future<GameSessionHandle> createLobby(final CreateGameLobbyRequest request) =>
      createLobbyForAuthUser(request);

  Future<GameSessionHandle> createLobbyForAuthUser(
    final CreateGameLobbyRequest request, {
    final String? authUserId,
  }) async {
    final decodedRequest = _roundTripCreateLobbyRequest(request);
    final lobbyId = 'local-lobby-${_nextLobbyId++}';
    final joinCode = _generateJoinCode();
    final participant = _createParticipant(
      displayName: decodedRequest.displayName,
      authUserId: authUserId,
    );
    final lobby = _LocalLobbyState(
      lobbyId: lobbyId,
      joinCode: joinCode,
      hostPlayerId: participant.playerId,
      gameName: decodedRequest.gameName,
      targetScore: decodedRequest.targetScore,
      visibility: decodedRequest.visibility,
      participantsByAccessToken: {participant.accessToken: participant},
      participantsByPlayerId: {participant.playerId: participant},
      seats: List<_LocalSeatState>.generate(
        4,
        (final index) => _LocalSeatState(seat: index),
      ),
    );

    _lobbies[lobbyId] = lobby;
    _lobbyIdByJoinCode[joinCode] = lobbyId;

    if (decodedRequest.preferredTeam != null) {
      final seat = _firstOpenSeatForTeam(lobby, decodedRequest.preferredTeam!);
      if (seat != null) {
        _claimParticipantSeat(
          lobby,
          participant,
          seat: seat,
          type: PlayerType.human,
        );
      }
    }

    _emitLobby(lobby);
    return _roundTripSessionHandle(
      GameSessionHandle(
        lobbyId: lobbyId,
        playerId: participant.playerId,
        accessToken: participant.accessToken,
        seat: participant.seat,
      ),
    );
  }

  @override
  Future<GameSessionHandle> joinLobby(final JoinGameLobbyRequest request) =>
      joinLobbyForAuthUser(request);

  Future<GameSessionHandle> joinLobbyForAuthUser(
    final JoinGameLobbyRequest request, {
    final String? authUserId,
  }) async {
    final decodedRequest = _roundTripJoinLobbyRequest(request);
    final lobbyId =
        _lobbyIdByJoinCode[decodedRequest.joinCode] ??
        (_lobbies.containsKey(decodedRequest.joinCode)
            ? decodedRequest.joinCode
            : null);
    if (lobbyId == null) {
      throw StateError('Unknown join code: ${decodedRequest.joinCode}');
    }
    final lobby = _requireLobby(lobbyId);
    if (lobby.state == GameLobbyState.closed) {
      throw StateError('Lobby is closed.');
    }

    final participant = _findParticipantByAuthUserId(lobby, authUserId);
    if (participant != null) {
      _markParticipantConnected(lobby, participant);
      if (decodedRequest.preferredTeam != null) {
        final seat = _firstOpenSeatForTeam(
          lobby,
          decodedRequest.preferredTeam!,
        );
        if (seat != null) {
          _claimParticipantSeat(
            lobby,
            participant,
            seat: seat,
            type: PlayerType.human,
          );
        }
      }
      _emitLobby(lobby);
      return _roundTripSessionHandle(
        GameSessionHandle(
          lobbyId: lobby.lobbyId,
          playerId: participant.playerId,
          accessToken: participant.accessToken,
          seat: participant.seat,
          matchId: lobby.matchId,
        ),
      );
    }

    final newParticipant = _createParticipant(
      displayName: decodedRequest.displayName,
      authUserId: authUserId,
    );
    lobby.participantsByAccessToken[newParticipant.accessToken] =
        newParticipant;
    lobby.participantsByPlayerId[newParticipant.playerId] = newParticipant;
    if (decodedRequest.preferredTeam != null) {
      final seat = _firstOpenSeatForTeam(lobby, decodedRequest.preferredTeam!);
      if (seat != null) {
        _claimParticipantSeat(
          lobby,
          newParticipant,
          seat: seat,
          type: PlayerType.human,
        );
      }
    }

    _emitLobby(lobby);
    return _roundTripSessionHandle(
      GameSessionHandle(
        lobbyId: lobby.lobbyId,
        playerId: newParticipant.playerId,
        accessToken: newParticipant.accessToken,
        seat: newParticipant.seat,
        matchId: lobby.matchId,
      ),
    );
  }

  @override
  Future<List<GameLobbyListEntry>> listGames() async {
    return <GameLobbyListEntry>[
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
                .where((final s) => s.state == GameLobbySeatState.occupied)
                .length,
          ),
    ];
  }

  String _hostDisplayName(final _LocalLobbyState lobby) {
    final host = lobby.participantsByPlayerId[lobby.hostPlayerId];
    return host?.displayName ?? 'Unknown';
  }

  @override
  Stream<GameLobbySnapshot> watchLobby(
    final String lobbyId, {
    required final String accessToken,
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
    final String lobbyId, {
    required final String accessToken,
    required final int seat,
    final PlayerType type = PlayerType.human,
    final String? automatedDisplayName,
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
    final String lobbyId, {
    required final String accessToken,
    required final bool isReady,
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
  Future<void> startMatch(
    final String lobbyId, {
    required final String accessToken,
  }) async {
    final lobby = _requireLobby(lobbyId);
    final participant = _requireParticipant(lobby, accessToken);
    if (participant.playerId != lobby.hostPlayerId) {
      throw StateError('Only the host can start the match.');
    }
    if (!_canStart(lobby)) {
      throw StateError('All seats must be occupied and ready before starting.');
    }
    if (lobby.runtime != null || lobby.matchId != null) {
      throw StateError('Match already started for this lobby.');
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
        .listen((final snapshot) => _handleBackendSnapshot(lobby, snapshot));
    await runtime.setAutomatedActionDelay(lobby.automatedActionDelay);
    _emitLobby(lobby);
    _emitConnection(
      lobby,
      const GameMatchConnectionSnapshot(state: GameMatchConnectionState.live),
    );
    await runtime.startGame(matchId);
  }

  @override
  Future<void> leaveLobby(
    final String lobbyId, {
    required final String accessToken,
  }) async {
    final lobby = _requireLobby(lobbyId);
    final participant = _requireParticipant(lobby, accessToken);
    if (lobby.matchId != null) {
      await leaveMatch(lobby.matchId!, accessToken: accessToken);
      return;
    }

    _removeParticipantFromLobby(lobby, participant);
    if (lobby.participantsByAccessToken.isEmpty) {
      await _closeLobby(lobby);
      return;
    }

    if (lobby.hostPlayerId == participant.playerId) {
      lobby.hostPlayerId = lobby.participantsByPlayerId.values.first.playerId;
    }
    _emitLobby(lobby);
  }

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

  @override
  Future<void> sendHeartbeat(
    final String lobbyId, {
    required final String accessToken,
  }) async {
    final lobby = _requireLobby(lobbyId);
    final participant = _requireParticipant(lobby, accessToken);
    _updateHeartbeat(lobby, participant);
  }

  Future<void> sendMatchHeartbeat(
    final String matchId, {
    required final String accessToken,
  }) async {
    final resolved = _requireActiveMatch(matchId, accessToken);
    _updateHeartbeat(resolved.lobby, resolved.participant);
  }

  void _updateHeartbeat(
    final _LocalLobbyState lobby,
    final _LocalParticipant participant,
  ) {
    participant.lastHeartbeatAt = DateTime.now();
    if (!participant.isConnected) {
      _markParticipantConnected(lobby, participant);
      _emitLobby(lobby);
    }
  }

  void sweepHeartbeats() {
    final now = DateTime.now();
    for (final lobby in _lobbies.values.toList()) {
      var changed = false;
      for (final participant in lobby.participantsByPlayerId.values) {
        if (!participant.isConnected) continue;
        final seat = participant.seat;
        if (seat != null && lobby.seats[seat].isBot) continue;
        if (now.difference(participant.lastHeartbeatAt) >
            _heartbeatConfig.timeout) {
          participant.isConnected = false;
          if (seat != null) {
            final seatState = lobby.seats[seat];
            if (seatState.playerId == participant.playerId) {
              seatState.isConnected = false;
            }
          }
          changed = true;
        }
      }
      if (changed) {
        _emitLobby(lobby);
      }
    }
  }

  void dispose() {
    _heartbeatSweepTimer?.cancel();
    _heartbeatSweepTimer = null;
  }

  _LocalParticipant _createParticipant({
    required final String displayName,
    final String? authUserId,
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
  int? _firstOpenSeatForTeam(final _LocalLobbyState lobby, final int team) {
    final teamSeats = team == 0 ? <int>[0, 2] : <int>[1, 3];
    for (final seatIndex in teamSeats) {
      if (lobby.seats[seatIndex].state == GameLobbySeatState.open) {
        return seatIndex;
      }
    }
    return null;
  }

  _LocalParticipant? _findParticipantByAuthUserId(
    final _LocalLobbyState lobby,
    final String? authUserId,
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
    final _LocalLobbyState lobby,
    final _LocalParticipant participant,
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

  _LocalLobbyState _requireLobby(final String lobbyId) {
    final lobby = _lobbies[lobbyId];
    if (lobby == null) {
      throw StateError('Unknown lobbyId: $lobbyId');
    }
    return lobby;
  }

  _LocalParticipant _requireParticipant(
    final _LocalLobbyState lobby,
    final String accessToken,
  ) {
    final participant = lobby.participantsByAccessToken[accessToken];
    if (participant == null) {
      throw StateError('Unknown access token for lobby ${lobby.lobbyId}.');
    }
    return participant;
  }

  ({_LocalLobbyState lobby, _LocalParticipant participant}) _requireActiveMatch(
    final String matchId,
    final String accessToken,
  ) {
    final lobby = _lobbies.values.firstWhere(
      (final entry) => entry.matchId == matchId,
      orElse: () => throw StateError('Unknown matchId: $matchId'),
    );
    final participant = _requireParticipant(lobby, accessToken);
    if (lobby.runtime == null) {
      throw StateError('Match is not active.');
    }
    return (lobby: lobby, participant: participant);
  }

  void _ensureSeatIndex(final _LocalLobbyState lobby, final int seat) {
    if (seat < 0 || seat >= lobby.seats.length) {
      throw RangeError.range(seat, 0, lobby.seats.length - 1, 'seat');
    }
  }

  void _ensureLobbyNotActive(final _LocalLobbyState lobby) {
    if (lobby.matchId != null || lobby.runtime != null) {
      throw StateError('Cannot change seats after the match has started.');
    }
  }

  void _claimParticipantSeat(
    final _LocalLobbyState lobby,
    final _LocalParticipant participant, {
    required final int seat,
    required final PlayerType type,
  }) {
    final targetSeat = lobby.seats[seat];
    if (targetSeat.isOccupiedByDifferentParticipant(participant.playerId)) {
      throw StateError('Seat $seat is already occupied.');
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
    final _LocalLobbyState lobby,
    final int seat,
    final String displayName,
  ) {
    final targetSeat = lobby.seats[seat];
    if (targetSeat.state == GameLobbySeatState.occupied && !targetSeat.isBot) {
      throw StateError('Seat $seat is already occupied by a player.');
    }

    targetSeat.assignBot(
      playerId: 'local-bot-${lobby.lobbyId}-$seat',
      displayName: displayName,
    );
  }

  bool _canStart(final _LocalLobbyState lobby) {
    final allSeatsOccupied = lobby.seats.every(
      (final seat) => seat.state == GameLobbySeatState.occupied,
    );
    final participantsReady = lobby.participantsByPlayerId.values.every(
      (final participant) => participant.isReady && participant.seat != null,
    );
    return allSeatsOccupied && participantsReady;
  }

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

  void _removeParticipantFromLobby(
    final _LocalLobbyState lobby,
    final _LocalParticipant participant,
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

  Future<void> _closeLobby(final _LocalLobbyState lobby) async {
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
