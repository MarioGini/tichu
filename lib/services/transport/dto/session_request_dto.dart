import 'package:meta/meta.dart';
import 'package:tichu/game/game_session.dart';
import 'package:tichu/services/transport/dto/dto_helpers.dart';

@immutable
class CreateGameLobbyRequestDto {
  final String displayName;
  final String gameName;
  final int targetScore;
  final int? preferredTeam;
  final String visibility;

  const CreateGameLobbyRequestDto({
    required this.displayName,
    required this.gameName,
    required this.targetScore,
    required this.preferredTeam,
    required this.visibility,
  });

  factory CreateGameLobbyRequestDto.fromDomain(
    CreateGameLobbyRequest request,
  ) => CreateGameLobbyRequestDto(
    displayName: request.displayName,
    gameName: request.gameName,
    targetScore: request.targetScore,
    preferredTeam: request.preferredTeam,
    visibility: request.visibility.name,
  );

  factory CreateGameLobbyRequestDto.fromJson(Map<String, dynamic> json) =>
      CreateGameLobbyRequestDto(
        displayName: json['displayName'] as String,
        gameName: (json['gameName'] as String?) ?? '',
        targetScore: (json['targetScore'] as num).toInt(),
        preferredTeam: (json['preferredTeam'] as num?)?.toInt(),
        visibility: (json['visibility'] as String?) ?? 'public',
      );

  Map<String, dynamic> toJson() => {
    'displayName': displayName,
    'gameName': gameName,
    'targetScore': targetScore,
    'preferredTeam': preferredTeam,
    'visibility': visibility,
  };

  CreateGameLobbyRequest toDomain() => CreateGameLobbyRequest(
    displayName: displayName,
    gameName: gameName,
    targetScore: targetScore,
    preferredTeam: preferredTeam,
    visibility: enumByName(GameLobbyVisibility.values, visibility),
  );
}

@immutable
class JoinGameLobbyRequestDto {
  final String joinCode;
  final String displayName;
  final int? preferredTeam;

  const JoinGameLobbyRequestDto({
    required this.joinCode,
    required this.displayName,
    required this.preferredTeam,
  });

  factory JoinGameLobbyRequestDto.fromDomain(JoinGameLobbyRequest request) =>
      JoinGameLobbyRequestDto(
        joinCode: request.joinCode,
        displayName: request.displayName,
        preferredTeam: request.preferredTeam,
      );

  factory JoinGameLobbyRequestDto.fromJson(Map<String, dynamic> json) =>
      JoinGameLobbyRequestDto(
        joinCode: json['joinCode'] as String,
        displayName: json['displayName'] as String,
        preferredTeam: (json['preferredTeam'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
    'joinCode': joinCode,
    'displayName': displayName,
    'preferredTeam': preferredTeam,
  };

  JoinGameLobbyRequest toDomain() => JoinGameLobbyRequest(
    joinCode: joinCode,
    displayName: displayName,
    preferredTeam: preferredTeam,
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

  factory GameSessionHandleDto.fromDomain(GameSessionHandle handle) =>
      GameSessionHandleDto(
        lobbyId: handle.lobbyId,
        playerId: handle.playerId,
        accessToken: handle.accessToken,
        seat: handle.seat,
        matchId: handle.matchId,
      );

  factory GameSessionHandleDto.fromJson(Map<String, dynamic> json) =>
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
