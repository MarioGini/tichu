import 'package:meta/meta.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';

enum GameMatchConnectionState {
  connecting,
  live,
  reconnecting,
  offline,
  closed,
}

@immutable
class GameMatchConnectionSnapshot {
  final GameMatchConnectionState state;
  final String? detail;
  final DateTime? updatedAt;

  const GameMatchConnectionSnapshot({
    required this.state,
    this.detail,
    this.updatedAt,
  });
}

@immutable
class GameMatchView {
  final String lobbyId;
  final String matchId;
  final String selfPlayerId;
  final int selfSeat;
  final int revision;
  final bool roundAcknowledgementRequired;
  final PlayerSnapshot snapshot;

  const GameMatchView({
    required this.lobbyId,
    required this.matchId,
    required this.selfPlayerId,
    required this.selfSeat,
    required this.revision,
    required this.roundAcknowledgementRequired,
    required this.snapshot,
  });
}

@immutable
class GameActionSubmission {
  final String clientActionId;
  final GameAction action;
  final int? expectedRevision;

  const GameActionSubmission({
    required this.clientActionId,
    required this.action,
    this.expectedRevision,
  });
}

@immutable
class RoundSummaryAcknowledgement {
  final String clientActionId;
  final int roundNumber;
  final int? expectedRevision;

  const RoundSummaryAcknowledgement({
    required this.clientActionId,
    required this.roundNumber,
    this.expectedRevision,
  });
}

/// Authoritative live-match contract for transport-backed gameplay.
///
/// A cloud service should stream [GameMatchView] values that wrap the existing
/// player-specific snapshot with server revision metadata and connection state.
/// Client actions are submitted with idempotency keys so reconnects and retry
/// loops do not double-apply turns.
abstract interface class GameMatchService {
  Stream<GameMatchView> watchMatch(
    final String matchId, {
    required final String accessToken,
  });

  Stream<GameMatchConnectionSnapshot> watchConnection(
    final String matchId, {
    required final String accessToken,
  });

  Future<void> submitAction(
    final String matchId,
    final GameActionSubmission submission, {
    required final String accessToken,
  });

  Future<void> acknowledgeRoundSummary(
    final String matchId,
    final RoundSummaryAcknowledgement acknowledgement, {
    required final String accessToken,
  });

  Future<void> leaveMatch(
    final String matchId, {
    required final String accessToken,
  });
}

abstract interface class AdjustableAutomatedActionDelay {
  Future<void> setMatchAutomatedActionDelay(
    final String matchId, {
    required final String accessToken,
    required final Duration delay,
  });
}
