import 'package:meta/meta.dart';
import 'package:tichu/game/game_session.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/services/transport/dto/dto_helpers.dart';

export 'package:tichu/services/transport/dto/session_request_dto.dart';

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
  final String gameName;
  final int targetScore;
  final String state;
  final String visibility;
  final bool canStart;
  final bool isLocalPlayerHost;
  final List<GameLobbySeatSnapshotDto> seats;

  const GameLobbySnapshotDto({
    required this.lobbyId,
    required this.joinCode,
    required this.localPlayerId,
    required this.hostPlayerId,
    required this.matchId,
    required this.gameName,
    required this.targetScore,
    required this.state,
    required this.visibility,
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
        gameName: snapshot.gameName,
        targetScore: snapshot.targetScore,
        state: snapshot.state.name,
        visibility: snapshot.visibility.name,
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
        gameName: (json['gameName'] as String?) ?? '',
        targetScore: (json['targetScore'] as num).toInt(),
        state: json['state'] as String,
        visibility: (json['visibility'] as String?) ?? 'public',
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
    'gameName': gameName,
    'targetScore': targetScore,
    'state': state,
    'visibility': visibility,
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
    gameName: gameName,
    targetScore: targetScore,
    state: enumByName(GameLobbyState.values, state),
    visibility: enumByName(GameLobbyVisibility.values, visibility),
    canStart: canStart,
    isLocalPlayerHost: isLocalPlayerHost,
    seats: [for (final seat in seats) seat.toDomain()],
  );
}

@immutable
class GameLobbyListEntryDto {
  final String lobbyId;
  final String gameName;
  final String hostDisplayName;
  final int targetScore;
  final String visibility;
  final int occupiedSeats;
  final int totalSeats;

  const GameLobbyListEntryDto({
    required this.lobbyId,
    required this.gameName,
    required this.hostDisplayName,
    required this.targetScore,
    required this.visibility,
    required this.occupiedSeats,
    required this.totalSeats,
  });

  factory GameLobbyListEntryDto.fromDomain(final GameLobbyListEntry entry) =>
      GameLobbyListEntryDto(
        lobbyId: entry.lobbyId,
        gameName: entry.gameName,
        hostDisplayName: entry.hostDisplayName,
        targetScore: entry.targetScore,
        visibility: entry.visibility.name,
        occupiedSeats: entry.occupiedSeats,
        totalSeats: entry.totalSeats,
      );

  factory GameLobbyListEntryDto.fromJson(final Map<String, dynamic> json) =>
      GameLobbyListEntryDto(
        lobbyId: json['lobbyId'] as String,
        gameName: (json['gameName'] as String?) ?? '',
        hostDisplayName: json['hostDisplayName'] as String,
        targetScore: (json['targetScore'] as num).toInt(),
        visibility: (json['visibility'] as String?) ?? 'public',
        occupiedSeats: (json['occupiedSeats'] as num).toInt(),
        totalSeats: (json['totalSeats'] as num?)?.toInt() ?? 4,
      );

  Map<String, dynamic> toJson() => {
    'lobbyId': lobbyId,
    'gameName': gameName,
    'hostDisplayName': hostDisplayName,
    'targetScore': targetScore,
    'visibility': visibility,
    'occupiedSeats': occupiedSeats,
    'totalSeats': totalSeats,
  };

  GameLobbyListEntry toDomain() => GameLobbyListEntry(
    lobbyId: lobbyId,
    gameName: gameName,
    hostDisplayName: hostDisplayName,
    targetScore: targetScore,
    visibility: enumByName(GameLobbyVisibility.values, visibility),
    occupiedSeats: occupiedSeats,
    totalSeats: totalSeats,
  );
}
