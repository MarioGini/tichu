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
import 'package:tichu/services/request_rejected_exception.dart';
import 'package:tichu/services/transport/dto/match_dto.dart' as match_dto;
import 'package:tichu/services/transport/dto/session_dto.dart' as session_dto;

part 'local_lobby_api.dart';
part 'local_lobby_helpers.dart';
part 'local_lobby_state.dart';
part 'local_match_api.dart';
part 'local_publish_helpers.dart';
part 'local_table_state.dart';

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

class LocalGameTableService extends _LocalTableBase
    with _LocalLobbyApi, _LocalMatchApi
    implements GameSessionService {
  LocalGameTableService({
    super.runtimeFactory,
    super.projectionEngine,
    super.projectionStore,
    super.stateStore,
    super.heartbeatConfig,
  });

  @override
  Future<GameSessionHandle> createLobby(CreateGameLobbyRequest request) =>
      createLobbyForAuthUser(request);

  Future<GameSessionHandle> createLobbyForAuthUser(
    CreateGameLobbyRequest request, {
    String? authUserId,
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
        (index) => _LocalSeatState(seat: index),
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
  Future<GameSessionHandle> joinLobby(JoinGameLobbyRequest request) =>
      joinLobbyForAuthUser(request);

  Future<GameSessionHandle> joinLobbyForAuthUser(
    JoinGameLobbyRequest request, {
    String? authUserId,
  }) async {
    final decodedRequest = _roundTripJoinLobbyRequest(request);
    final lobbyId =
        _lobbyIdByJoinCode[decodedRequest.joinCode] ??
        (_lobbies.containsKey(decodedRequest.joinCode)
            ? decodedRequest.joinCode
            : null);
    if (lobbyId == null) {
      throw RequestRejectedException(
        'Unknown join code: ${decodedRequest.joinCode}',
      );
    }
    final lobby = _requireLobby(lobbyId);
    if (lobby.state == GameLobbyState.closed) {
      throw const RequestRejectedException('Lobby is closed.');
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
  Future<void> leaveLobby(String lobbyId, {required String accessToken}) async {
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
  Future<void> sendHeartbeat(
    String lobbyId, {
    required String accessToken,
  }) async {
    final lobby = _requireLobby(lobbyId);
    final participant = _requireParticipant(lobby, accessToken);
    _updateHeartbeat(lobby, participant);
  }

  @override
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
}
