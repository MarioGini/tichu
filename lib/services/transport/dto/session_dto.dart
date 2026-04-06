import 'package:meta/meta.dart';
import 'package:tichu/game/game_session.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/services/transport/dto/dto_helpers.dart';

@immutable
class CreateGameLobbyRequestDto {
  final String displayName;
  final int targetScore;
  final int? preferredSeat;

  const CreateGameLobbyRequestDto({
    required this.displayName,
    required this.targetScore,
    required this.preferredSeat,
  });

  factory CreateGameLobbyRequestDto.fromDomain(
    final CreateGameLobbyRequest request,
  ) => CreateGameLobbyRequestDto(
    displayName: request.displayName,
    targetScore: request.targetScore,
    preferredSeat: request.preferredSeat,
  );

  factory CreateGameLobbyRequestDto.fromJson(final Map<String, dynamic> json) =>
      CreateGameLobbyRequestDto(
        displayName: json['displayName'] as String,
        targetScore: (json['targetScore'] as num).toInt(),
        preferredSeat: (json['preferredSeat'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
    'displayName': displayName,
    'targetScore': targetScore,
    'preferredSeat': preferredSeat,
  };

  CreateGameLobbyRequest toDomain() => CreateGameLobbyRequest(
    displayName: displayName,
    targetScore: targetScore,
    preferredSeat: preferredSeat,
  );
}

@immutable
class JoinGameLobbyRequestDto {
  final String joinCode;
  final String displayName;
  final int? preferredSeat;

  const JoinGameLobbyRequestDto({
    required this.joinCode,
    required this.displayName,
    required this.preferredSeat,
  });

  factory JoinGameLobbyRequestDto.fromDomain(
    final JoinGameLobbyRequest request,
  ) => JoinGameLobbyRequestDto(
    joinCode: request.joinCode,
    displayName: request.displayName,
    preferredSeat: request.preferredSeat,
  );

  factory JoinGameLobbyRequestDto.fromJson(final Map<String, dynamic> json) =>
      JoinGameLobbyRequestDto(
        joinCode: json['joinCode'] as String,
        displayName: json['displayName'] as String,
        preferredSeat: (json['preferredSeat'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
    'joinCode': joinCode,
    'displayName': displayName,
    'preferredSeat': preferredSeat,
  };

  JoinGameLobbyRequest toDomain() => JoinGameLobbyRequest(
    joinCode: joinCode,
    displayName: displayName,
    preferredSeat: preferredSeat,
  );
}

@immutable
class GameSessionHandleDto {
  final String lobbyId;
  final String playerId;
  final String accessToken;
  final int? seat;
  final String? matchId;

  const GameSessionHandleDto({
    required this.lobbyId,
    required this.playerId,
    required this.accessToken,
    required this.seat,
    required this.matchId,
  });

  factory GameSessionHandleDto.fromDomain(final GameSessionHandle handle) =>
      GameSessionHandleDto(
        lobbyId: handle.lobbyId,
        playerId: handle.playerId,
        accessToken: handle.accessToken,
        seat: handle.seat,
        matchId: handle.matchId,
      );

  factory GameSessionHandleDto.fromJson(final Map<String, dynamic> json) =>
      GameSessionHandleDto(
        lobbyId: json['lobbyId'] as String,
        playerId: json['playerId'] as String,
        accessToken: json['accessToken'] as String,
        seat: (json['seat'] as num?)?.toInt(),
        matchId: json['matchId'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'lobbyId': lobbyId,
    'playerId': playerId,
    'accessToken': accessToken,
    'seat': seat,
    'matchId': matchId,
  };

  GameSessionHandle toDomain() => GameSessionHandle(
    lobbyId: lobbyId,
    playerId: playerId,
    accessToken: accessToken,
    seat: seat,
    matchId: matchId,
  );
}

@immutable
class GameLobbySeatSnapshotDto {
  final int seat;
  final String state;
  final String type;
  final String? playerId;
  final String? displayName;
  final bool isReady;
  final bool isConnected;

  const GameLobbySeatSnapshotDto({
    required this.seat,
    required this.state,
    required this.type,
    required this.playerId,
    required this.displayName,
    required this.isReady,
    required this.isConnected,
  });

  factory GameLobbySeatSnapshotDto.fromDomain(
    final GameLobbySeatSnapshot snapshot,
  ) => GameLobbySeatSnapshotDto(
    seat: snapshot.seat,
    state: snapshot.state.name,
    type: snapshot.type.name,
    playerId: snapshot.playerId,
    displayName: snapshot.displayName,
    isReady: snapshot.isReady,
    isConnected: snapshot.isConnected,
  );

  factory GameLobbySeatSnapshotDto.fromJson(final Map<String, dynamic> json) =>
      GameLobbySeatSnapshotDto(
        seat: (json['seat'] as num).toInt(),
        state: json['state'] as String,
        type: json['type'] as String,
        playerId: json['playerId'] as String?,
        displayName: json['displayName'] as String?,
        isReady: json['isReady'] as bool? ?? false,
        isConnected: json['isConnected'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
    'seat': seat,
    'state': state,
    'type': type,
    'playerId': playerId,
    'displayName': displayName,
    'isReady': isReady,
    'isConnected': isConnected,
  };

  GameLobbySeatSnapshot toDomain() => GameLobbySeatSnapshot(
    seat: seat,
    state: enumByName(GameLobbySeatState.values, state),
    type: enumByName(PlayerType.values, type),
    playerId: playerId,
    displayName: displayName,
    isReady: isReady,
    isConnected: isConnected,
  );
}

@immutable
class GameLobbySnapshotDto {
  final String lobbyId;
  final String? joinCode;
  final String localPlayerId;
  final String hostPlayerId;
  final String? matchId;
  final int targetScore;
  final String state;
  final bool canStart;
  final bool isLocalPlayerHost;
  final List<GameLobbySeatSnapshotDto> seats;

  const GameLobbySnapshotDto({
    required this.lobbyId,
    required this.joinCode,
    required this.localPlayerId,
    required this.hostPlayerId,
    required this.matchId,
    required this.targetScore,
    required this.state,
    required this.canStart,
    required this.isLocalPlayerHost,
    required this.seats,
  });

  factory GameLobbySnapshotDto.fromDomain(final GameLobbySnapshot snapshot) =>
      GameLobbySnapshotDto(
        lobbyId: snapshot.lobbyId,
        joinCode: snapshot.joinCode,
        localPlayerId: snapshot.localPlayerId,
        hostPlayerId: snapshot.hostPlayerId,
        matchId: snapshot.matchId,
        targetScore: snapshot.targetScore,
        state: snapshot.state.name,
        canStart: snapshot.canStart,
        isLocalPlayerHost: snapshot.isLocalPlayerHost,
        seats: [
          for (final seat in snapshot.seats)
            GameLobbySeatSnapshotDto.fromDomain(seat),
        ],
      );

  factory GameLobbySnapshotDto.fromJson(final Map<String, dynamic> json) =>
      GameLobbySnapshotDto(
        lobbyId: json['lobbyId'] as String,
        joinCode: json['joinCode'] as String?,
        localPlayerId: json['localPlayerId'] as String,
        hostPlayerId: json['hostPlayerId'] as String,
        matchId: json['matchId'] as String?,
        targetScore: (json['targetScore'] as num).toInt(),
        state: json['state'] as String,
        canStart: json['canStart'] as bool? ?? false,
        isLocalPlayerHost: json['isLocalPlayerHost'] as bool? ?? false,
        seats: decodeMapList(
          json['seats'],
        ).map(GameLobbySeatSnapshotDto.fromJson).toList(),
      );

  Map<String, dynamic> toJson() => {
    'lobbyId': lobbyId,
    'joinCode': joinCode,
    'localPlayerId': localPlayerId,
    'hostPlayerId': hostPlayerId,
    'matchId': matchId,
    'targetScore': targetScore,
    'state': state,
    'canStart': canStart,
    'isLocalPlayerHost': isLocalPlayerHost,
    'seats': [for (final seat in seats) seat.toJson()],
  };

  GameLobbySnapshot toDomain() => GameLobbySnapshot(
    lobbyId: lobbyId,
    joinCode: joinCode,
    localPlayerId: localPlayerId,
    hostPlayerId: hostPlayerId,
    matchId: matchId,
    targetScore: targetScore,
    state: enumByName(GameLobbyState.values, state),
    canStart: canStart,
    isLocalPlayerHost: isLocalPlayerHost,
    seats: [for (final seat in seats) seat.toDomain()],
  );
}
