import 'package:meta/meta.dart';

@immutable
class ProjectedLobbyView {
  const ProjectedLobbyView({
    required this.lobbyId,
    required this.authUserId,
    required this.accessToken,
    required this.playerId,
    required this.payload,
  });

  final String lobbyId;
  final String authUserId;
  final String accessToken;
  final String playerId;
  final Map<String, dynamic> payload;
}

@immutable
class ProjectedMatchView {
  const ProjectedMatchView({
    required this.lobbyId,
    required this.matchId,
    required this.authUserId,
    required this.accessToken,
    required this.playerId,
    required this.revision,
    required this.payload,
  });

  final String lobbyId;
  final String matchId;
  final String authUserId;
  final String accessToken;
  final String playerId;
  final int revision;
  final Map<String, dynamic> payload;
}

@immutable
class ProjectedConnectionView {
  const ProjectedConnectionView({
    required this.lobbyId,
    required this.matchId,
    required this.authUserId,
    required this.accessToken,
    required this.playerId,
    required this.payload,
  });

  final String lobbyId;
  final String matchId;
  final String authUserId;
  final String accessToken;
  final String playerId;
  final Map<String, dynamic> payload;
}

abstract interface class GameTableProjectionStore {
  Future<void> replaceLobbyViews(
    final String lobbyId,
    final List<ProjectedLobbyView> views,
  );

  Future<void> replaceMatchViews(
    final String matchId,
    final List<ProjectedMatchView> views,
  );

  Future<void> replaceConnectionViews(
    final String matchId,
    final List<ProjectedConnectionView> views,
  );

  Future<void> deleteLobbyState(final String lobbyId, {final String? matchId});
}

class NoopGameTableProjectionStore implements GameTableProjectionStore {
  const NoopGameTableProjectionStore();

  @override
  Future<void> replaceLobbyViews(
    final String lobbyId,
    final List<ProjectedLobbyView> views,
  ) async {}

  @override
  Future<void> replaceMatchViews(
    final String matchId,
    final List<ProjectedMatchView> views,
  ) async {}

  @override
  Future<void> replaceConnectionViews(
    final String matchId,
    final List<ProjectedConnectionView> views,
  ) async {}

  @override
  Future<void> deleteLobbyState(
    final String lobbyId, {
    final String? matchId,
  }) async {}
}
