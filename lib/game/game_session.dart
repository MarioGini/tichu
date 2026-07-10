import 'package:meta/meta.dart';
import 'package:tichu/game/game_types.dart';

enum GameLobbyState {
  assembling,
  readyCheck,
  starting,
  active,
  finished,
  closed,
}

enum GameLobbySeatState { open, occupied, locked }

enum GameLobbyVisibility { public, private }

@immutable
class CreateGameLobbyRequest {
  final String displayName;
  final String gameName;
  final int targetScore;
  final int? preferredTeam;
  final GameLobbyVisibility visibility;

  const CreateGameLobbyRequest({
    required this.displayName,
    this.gameName = '',
    this.targetScore = 1000,
    this.preferredTeam,
    this.visibility = GameLobbyVisibility.public,
  });
}

@immutable
class JoinGameLobbyRequest {
  final String joinCode;
  final String displayName;
  final int? preferredTeam;

  const JoinGameLobbyRequest({
    required this.joinCode,
    required this.displayName,
    this.preferredTeam,
  });
}

@immutable
class GameSessionHandle {
  final String lobbyId;
  final String playerId;
  final String accessToken;
  final int? seat;
  final String? matchId;

  const GameSessionHandle({
    required this.lobbyId,
    required this.playerId,
    required this.accessToken,
    this.seat,
    this.matchId,
  });

  GameSessionHandle copyWith({
    final String? lobbyId,
    final String? playerId,
    final String? accessToken,
    final int? seat,
    final String? matchId,
  }) => GameSessionHandle(
    lobbyId: lobbyId ?? this.lobbyId,
    playerId: playerId ?? this.playerId,
    accessToken: accessToken ?? this.accessToken,
    seat: seat ?? this.seat,
    matchId: matchId ?? this.matchId,
  );
}

@immutable
class GameLobbySeatSnapshot {
  final int seat;
  final GameLobbySeatState state;
  final PlayerType type;
  final String? playerId;
  final String? displayName;
  final bool isReady;
  final bool isConnected;

  const GameLobbySeatSnapshot({
    required this.seat,
    this.state = GameLobbySeatState.open,
    this.type = PlayerType.human,
    this.playerId,
    this.displayName,
    this.isReady = false,
    this.isConnected = false,
  });
}

@immutable
class GameLobbySnapshot {
  final String lobbyId;
  final String? joinCode;
  final String localPlayerId;
  final String hostPlayerId;
  final String? matchId;
  final String gameName;
  final int targetScore;
  final GameLobbyState state;
  final GameLobbyVisibility visibility;
  final bool canStart;
  final bool isLocalPlayerHost;
  final List<GameLobbySeatSnapshot> seats;

  const GameLobbySnapshot({
    required this.lobbyId,
    this.joinCode,
    required this.localPlayerId,
    required this.hostPlayerId,
    this.matchId,
    this.gameName = '',
    required this.targetScore,
    required this.state,
    this.visibility = GameLobbyVisibility.public,
    required this.canStart,
    required this.isLocalPlayerHost,
    this.seats = const <GameLobbySeatSnapshot>[],
  });
}

@immutable
class GameLobbyListEntry {
  final String lobbyId;
  final String gameName;
  final String hostDisplayName;
  final int targetScore;
  final GameLobbyVisibility visibility;
  final int occupiedSeats;
  final int totalSeats;

  const GameLobbyListEntry({
    required this.lobbyId,
    required this.gameName,
    required this.hostDisplayName,
    required this.targetScore,
    required this.visibility,
    required this.occupiedSeats,
    this.totalSeats = 4,
  });
}

/// Lobby and session lifecycle contract for multiplayer-capable backends.
///
/// This sits above live gameplay. A cloud implementation should use this for
/// table creation, seat claims, readiness, reconnect, and match start.
abstract interface class GameSessionService {
  Future<GameSessionHandle> createLobby(final CreateGameLobbyRequest request);

  Future<GameSessionHandle> joinLobby(final JoinGameLobbyRequest request);

  Future<List<GameLobbyListEntry>> listGames();

  Stream<GameLobbySnapshot> watchLobby(
    final String lobbyId, {
    required final String accessToken,
  });

  Future<void> claimSeat(
    final String lobbyId, {
    required final String accessToken,
    required final int seat,
    final PlayerType type = PlayerType.human,
    final String? automatedDisplayName,
  });

  Future<void> setReadyState(
    final String lobbyId, {
    required final String accessToken,
    required final bool isReady,
  });

  Future<void> startMatch(
    final String lobbyId, {
    required final String accessToken,
  });

  Future<void> leaveLobby(
    final String lobbyId, {
    required final String accessToken,
  });

  Future<void> sendHeartbeat(
    final String lobbyId, {
    required final String accessToken,
  });
}
