import 'dart:async';
import 'dart:convert';

import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_match.dart';
import 'package:tichu/game/game_session.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/services/transport/dto/match_dto.dart' as match_dto;

class FakeGameMatchService
    implements GameMatchService, AdjustableAutomatedActionDelay {
  FakeGameMatchService({
    this.matchId = 'test-game',
    this.lobbyId = 'test-lobby',
    this.playerId = 'player-0',
    this.selfSeat = 0,
    this.accessToken = 'test-token',
  }) : sessionHandle = GameSessionHandle(
         lobbyId: lobbyId,
         playerId: playerId,
         accessToken: accessToken,
         seat: selfSeat,
         matchId: matchId,
       );

  final String matchId;
  final String lobbyId;
  final String playerId;
  final int selfSeat;
  final String accessToken;
  final GameSessionHandle sessionHandle;

  final StreamController<GameMatchView> _matchController =
      StreamController<GameMatchView>.broadcast();
  final List<GameAction> actions = <GameAction>[];
  final List<GameActionSubmission> submissions = <GameActionSubmission>[];
  final List<RoundSummaryAcknowledgement> acknowledgements =
      <RoundSummaryAcknowledgement>[];
  Duration? automatedActionDelay;
  GameMatchView? _latestView;

  void emit(
    final PlayerSnapshot snapshot, {
    final int revision = 1,
    final bool roundAcknowledgementRequired = false,
    final int? selfSeat,
  }) {
    final resolvedSelfSeat =
        selfSeat ??
        snapshot.players
            .firstWhere((final player) => player.id == playerId)
            .seat;
    final view = GameMatchView(
      lobbyId: lobbyId,
      matchId: matchId,
      selfPlayerId: playerId,
      selfSeat: resolvedSelfSeat,
      revision: revision,
      roundAcknowledgementRequired: roundAcknowledgementRequired,
      snapshot: snapshot,
    );
    final dto = match_dto.GameMatchViewDto.fromDomain(view);
    final roundTrippedView = match_dto.GameMatchViewDto.fromJson(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(dto.toJson())) as Map),
    ).toDomain();
    _latestView = roundTrippedView;
    _matchController.add(roundTrippedView);
  }

  Future<void> close() async {
    await _matchController.close();
  }

  @override
  Stream<GameMatchView> watchMatch(
    final String matchId, {
    required final String accessToken,
  }) async* {
    final latestView = _latestView;
    if (latestView != null) {
      yield latestView;
    }
    yield* _matchController.stream;
  }

  @override
  Stream<GameMatchConnectionSnapshot> watchConnection(
    final String matchId, {
    required final String accessToken,
  }) async* {
    yield const GameMatchConnectionSnapshot(
      state: GameMatchConnectionState.live,
    );
  }

  @override
  Future<void> submitAction(
    final String matchId,
    final GameActionSubmission submission, {
    required final String accessToken,
  }) async {
    final dto = match_dto.GameActionSubmissionDto.fromDomain(submission);
    final roundTrippedSubmission = match_dto.GameActionSubmissionDto.fromJson(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(dto.toJson())) as Map),
    ).toDomain();
    submissions.add(roundTrippedSubmission);
    actions.add(roundTrippedSubmission.action);
  }

  @override
  Future<void> acknowledgeRoundSummary(
    final String matchId,
    final RoundSummaryAcknowledgement acknowledgement, {
    required final String accessToken,
  }) async {
    final dto = match_dto.RoundSummaryAcknowledgementDto.fromDomain(
      acknowledgement,
    );
    final roundTrippedAcknowledgement =
        match_dto.RoundSummaryAcknowledgementDto.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(jsonEncode(dto.toJson())) as Map,
          ),
        ).toDomain();
    acknowledgements.add(roundTrippedAcknowledgement);
  }

  @override
  Future<void> leaveMatch(
    final String matchId, {
    required final String accessToken,
  }) async {}

  @override
  Future<void> setMatchAutomatedActionDelay(
    final String matchId, {
    required final String accessToken,
    required final Duration delay,
  }) async {
    automatedActionDelay = delay;
  }
}
