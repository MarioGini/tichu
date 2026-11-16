import 'package:tichu/game/game_session.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/services/multiplayer/multiplayer_backend.dart';

/// Creates a private lobby, seats the local player, fills the other three
/// seats with bots and starts the match.
///
/// Returns a session handle with `seat` and `matchId` set, ready to be passed
/// straight to the game screen.
Future<GameSessionHandle> startSoloMatch(
  final MultiplayerBackend backend, {
  required final String displayName,
  final int targetScore = 1000,
}) async {
  final service = backend.sessionService;
  final handle = await service.createLobby(
    CreateGameLobbyRequest(
      displayName: displayName,
      gameName: '$displayName vs Bots',
      targetScore: targetScore,
      preferredTeam: 0,
      visibility: GameLobbyVisibility.private,
    ),
  );

  var lobby = await service
      .watchLobby(handle.lobbyId, accessToken: handle.accessToken)
      .first;

  // The local player must own a seat before the bots take the rest;
  // otherwise every seat ends up a bot and the start check fails.
  var localSeat = _localSeat(lobby, handle.playerId);
  if (localSeat == null) {
    final open = lobby.seats.firstWhere(
      (final s) => s.state == GameLobbySeatState.open,
    );
    await service.claimSeat(
      handle.lobbyId,
      accessToken: handle.accessToken,
      seat: open.seat,
    );
  }

  await service.setReadyState(
    handle.lobbyId,
    accessToken: handle.accessToken,
    isReady: true,
  );

  lobby = await service
      .watchLobby(handle.lobbyId, accessToken: handle.accessToken)
      .first;
  for (final seat in lobby.seats) {
    if (seat.state == GameLobbySeatState.open) {
      await service.claimSeat(
        handle.lobbyId,
        accessToken: handle.accessToken,
        seat: seat.seat,
        type: PlayerType.automated,
        automatedDisplayName: 'Bot ${seat.seat + 1}',
      );
    }
  }

  await service.startMatch(handle.lobbyId, accessToken: handle.accessToken);
  final active = await service
      .watchLobby(handle.lobbyId, accessToken: handle.accessToken)
      .firstWhere((final s) => s.matchId != null);
  localSeat = _localSeat(active, handle.playerId);
  return handle.copyWith(seat: localSeat?.seat, matchId: active.matchId);
}

GameLobbySeatSnapshot? _localSeat(
  final GameLobbySnapshot lobby,
  final String playerId,
) {
  for (final seat in lobby.seats) {
    if (seat.playerId == playerId) return seat;
  }
  return null;
}
