import 'package:meta/meta.dart';
import 'package:tichu/game/game_match.dart';
import 'package:tichu/services/transport/dto/action_dto.dart';
import 'package:tichu/services/transport/dto/dto_helpers.dart';
import 'package:tichu/services/transport/dto/snapshot_dto.dart';

@immutable
class GameMatchConnectionSnapshotDto {
  final String state;
  final String? detail;
  final String? updatedAt;

  const GameMatchConnectionSnapshotDto({
    required this.state,
    required this.detail,
    required this.updatedAt,
  });

  factory GameMatchConnectionSnapshotDto.fromDomain(
    final GameMatchConnectionSnapshot snapshot,
  ) => GameMatchConnectionSnapshotDto(
    state: snapshot.state.name,
    detail: snapshot.detail,
    updatedAt: snapshot.updatedAt?.toIso8601String(),
  );

  factory GameMatchConnectionSnapshotDto.fromJson(
    final Map<String, dynamic> json,
  ) => GameMatchConnectionSnapshotDto(
    state: json['state'] as String,
    detail: json['detail'] as String?,
    updatedAt: json['updatedAt'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'state': state,
    'detail': detail,
    'updatedAt': updatedAt,
  };

  GameMatchConnectionSnapshot toDomain() => GameMatchConnectionSnapshot(
    state: enumByName(GameMatchConnectionState.values, state),
    detail: detail,
    updatedAt: updatedAt == null ? null : DateTime.parse(updatedAt!),
  );
}

@immutable
class GameMatchViewDto {
  final String lobbyId;
  final String matchId;
  final String selfPlayerId;
  final int selfSeat;
  final int revision;
  final bool roundAcknowledgementRequired;
  final PlayerSnapshotDto snapshot;

  const GameMatchViewDto({
    required this.lobbyId,
    required this.matchId,
    required this.selfPlayerId,
    required this.selfSeat,
    required this.revision,
    required this.roundAcknowledgementRequired,
    required this.snapshot,
  });

  factory GameMatchViewDto.fromDomain(final GameMatchView view) =>
      GameMatchViewDto(
        lobbyId: view.lobbyId,
        matchId: view.matchId,
        selfPlayerId: view.selfPlayerId,
        selfSeat: view.selfSeat,
        revision: view.revision,
        roundAcknowledgementRequired: view.roundAcknowledgementRequired,
        snapshot: PlayerSnapshotDto.fromDomain(view.snapshot),
      );

  factory GameMatchViewDto.fromJson(final Map<String, dynamic> json) =>
      GameMatchViewDto(
        lobbyId: json['lobbyId'] as String,
        matchId: json['matchId'] as String,
        selfPlayerId: json['selfPlayerId'] as String,
        selfSeat: (json['selfSeat'] as num).toInt(),
        revision: (json['revision'] as num).toInt(),
        roundAcknowledgementRequired:
            json['roundAcknowledgementRequired'] as bool? ?? false,
        snapshot: PlayerSnapshotDto.fromJson(
          Map<String, dynamic>.from(json['snapshot'] as Map),
        ),
      );

  Map<String, dynamic> toJson() => {
    'lobbyId': lobbyId,
    'matchId': matchId,
    'selfPlayerId': selfPlayerId,
    'selfSeat': selfSeat,
    'revision': revision,
    'roundAcknowledgementRequired': roundAcknowledgementRequired,
    'snapshot': snapshot.toJson(),
  };

  GameMatchView toDomain() => GameMatchView(
    lobbyId: lobbyId,
    matchId: matchId,
    selfPlayerId: selfPlayerId,
    selfSeat: selfSeat,
    revision: revision,
    roundAcknowledgementRequired: roundAcknowledgementRequired,
    snapshot: snapshot.toDomain(),
  );
}

@immutable
class GameActionSubmissionDto {
  final String clientActionId;
  final GameActionDto action;
  final int? expectedRevision;

  const GameActionSubmissionDto({
    required this.clientActionId,
    required this.action,
    required this.expectedRevision,
  });

  factory GameActionSubmissionDto.fromDomain(
    final GameActionSubmission submission,
  ) => GameActionSubmissionDto(
    clientActionId: submission.clientActionId,
    action: GameActionDto.fromDomain(submission.action),
    expectedRevision: submission.expectedRevision,
  );

  factory GameActionSubmissionDto.fromJson(final Map<String, dynamic> json) =>
      GameActionSubmissionDto(
        clientActionId: json['clientActionId'] as String,
        action: GameActionDto.fromJson(
          Map<String, dynamic>.from(json['action'] as Map),
        ),
        expectedRevision: (json['expectedRevision'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
    'clientActionId': clientActionId,
    'action': action.toJson(),
    'expectedRevision': expectedRevision,
  };

  GameActionSubmission toDomain() => GameActionSubmission(
    clientActionId: clientActionId,
    action: action.toDomain(),
    expectedRevision: expectedRevision,
  );
}

@immutable
class RoundSummaryAcknowledgementDto {
  final String clientActionId;
  final int roundNumber;
  final int? expectedRevision;

  const RoundSummaryAcknowledgementDto({
    required this.clientActionId,
    required this.roundNumber,
    required this.expectedRevision,
  });

  factory RoundSummaryAcknowledgementDto.fromDomain(
    final RoundSummaryAcknowledgement acknowledgement,
  ) => RoundSummaryAcknowledgementDto(
    clientActionId: acknowledgement.clientActionId,
    roundNumber: acknowledgement.roundNumber,
    expectedRevision: acknowledgement.expectedRevision,
  );

  factory RoundSummaryAcknowledgementDto.fromJson(
    final Map<String, dynamic> json,
  ) => RoundSummaryAcknowledgementDto(
    clientActionId: json['clientActionId'] as String,
    roundNumber: (json['roundNumber'] as num).toInt(),
    expectedRevision: (json['expectedRevision'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'clientActionId': clientActionId,
    'roundNumber': roundNumber,
    'expectedRevision': expectedRevision,
  };

  RoundSummaryAcknowledgement toDomain() => RoundSummaryAcknowledgement(
    clientActionId: clientActionId,
    roundNumber: roundNumber,
    expectedRevision: expectedRevision,
  );
}
