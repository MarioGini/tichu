import 'package:meta/meta.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/services/transport/dto/dto_helpers.dart';

@immutable
class ScoreStateDto {
  final int roundNumber;
  final int teamOneTotal;
  final int teamTwoTotal;
  final int teamOneRound;
  final int teamTwoRound;
  final Map<String, int> playerRoundPoints;
  final bool roundComplete;
  final int targetScore;
  final bool gameComplete;
  final int? winningTeam;
  final List<String> finishOrder;
  final List<RoundScoreDto> rounds;
  final Map<String, String> tichuCalls;

  const ScoreStateDto({
    required this.roundNumber,
    required this.teamOneTotal,
    required this.teamTwoTotal,
    required this.teamOneRound,
    required this.teamTwoRound,
    required this.playerRoundPoints,
    required this.roundComplete,
    required this.targetScore,
    required this.gameComplete,
    required this.winningTeam,
    required this.finishOrder,
    required this.rounds,
    required this.tichuCalls,
  });

  factory ScoreStateDto.fromDomain(final ScoreState state) => ScoreStateDto(
    roundNumber: state.roundNumber,
    teamOneTotal: state.teamOneTotal,
    teamTwoTotal: state.teamTwoTotal,
    teamOneRound: state.teamOneRound,
    teamTwoRound: state.teamTwoRound,
    playerRoundPoints: state.playerRoundPoints,
    roundComplete: state.roundComplete,
    targetScore: state.targetScore,
    gameComplete: state.gameComplete,
    winningTeam: state.winningTeam,
    finishOrder: state.finishOrder,
    rounds: [for (final round in state.rounds) RoundScoreDto.fromDomain(round)],
    tichuCalls: state.tichuCalls.map(
      (final key, final value) => MapEntry(key, value.name),
    ),
  );

  factory ScoreStateDto.fromJson(final Map<String, dynamic> json) =>
      ScoreStateDto(
        roundNumber: (json['roundNumber'] as num).toInt(),
        teamOneTotal: (json['teamOneTotal'] as num).toInt(),
        teamTwoTotal: (json['teamTwoTotal'] as num).toInt(),
        teamOneRound: (json['teamOneRound'] as num).toInt(),
        teamTwoRound: (json['teamTwoRound'] as num).toInt(),
        playerRoundPoints: decodeIntMap(json['playerRoundPoints']),
        roundComplete: json['roundComplete'] as bool? ?? false,
        targetScore: (json['targetScore'] as num).toInt(),
        gameComplete: json['gameComplete'] as bool? ?? false,
        winningTeam: (json['winningTeam'] as num?)?.toInt(),
        finishOrder: decodeStringList(json['finishOrder']),
        rounds: decodeMapList(
          json['rounds'],
        ).map(RoundScoreDto.fromJson).toList(),
        tichuCalls: decodeStringMap(json['tichuCalls']),
      );

  Map<String, dynamic> toJson() => {
    'roundNumber': roundNumber,
    'teamOneTotal': teamOneTotal,
    'teamTwoTotal': teamTwoTotal,
    'teamOneRound': teamOneRound,
    'teamTwoRound': teamTwoRound,
    'playerRoundPoints': playerRoundPoints,
    'roundComplete': roundComplete,
    'targetScore': targetScore,
    'gameComplete': gameComplete,
    'winningTeam': winningTeam,
    'finishOrder': finishOrder,
    'rounds': [for (final round in rounds) round.toJson()],
    'tichuCalls': tichuCalls,
  };

  ScoreState toDomain() => ScoreState(
    roundNumber: roundNumber,
    teamOneTotal: teamOneTotal,
    teamTwoTotal: teamTwoTotal,
    teamOneRound: teamOneRound,
    teamTwoRound: teamTwoRound,
    playerRoundPoints: playerRoundPoints,
    roundComplete: roundComplete,
    targetScore: targetScore,
    gameComplete: gameComplete,
    winningTeam: winningTeam,
    finishOrder: finishOrder,
    rounds: [for (final round in rounds) round.toDomain()],
    tichuCalls: tichuCalls.map(
      (final key, final value) =>
          MapEntry(key, enumByName(TichuCall.values, value)),
    ),
  );
}

@immutable
class RoundScoreDto {
  final int roundNumber;
  final int teamOnePoints;
  final int teamTwoPoints;
  final int teamOneCardPoints;
  final int teamTwoCardPoints;
  final int teamOneBonusPoints;
  final int teamTwoBonusPoints;
  final List<String> finishOrder;
  final String roundEndType;

  const RoundScoreDto({
    required this.roundNumber,
    required this.teamOnePoints,
    required this.teamTwoPoints,
    required this.teamOneCardPoints,
    required this.teamTwoCardPoints,
    required this.teamOneBonusPoints,
    required this.teamTwoBonusPoints,
    required this.finishOrder,
    required this.roundEndType,
  });

  factory RoundScoreDto.fromDomain(final RoundScore round) => RoundScoreDto(
    roundNumber: round.roundNumber,
    teamOnePoints: round.teamOnePoints,
    teamTwoPoints: round.teamTwoPoints,
    teamOneCardPoints: round.teamOneCardPoints,
    teamTwoCardPoints: round.teamTwoCardPoints,
    teamOneBonusPoints: round.teamOneBonusPoints,
    teamTwoBonusPoints: round.teamTwoBonusPoints,
    finishOrder: round.finishOrder,
    roundEndType: round.roundEndType.name,
  );

  factory RoundScoreDto.fromJson(final Map<String, dynamic> json) =>
      RoundScoreDto(
        roundNumber: (json['roundNumber'] as num).toInt(),
        teamOnePoints: (json['teamOnePoints'] as num).toInt(),
        teamTwoPoints: (json['teamTwoPoints'] as num).toInt(),
        teamOneCardPoints: (json['teamOneCardPoints'] as num).toInt(),
        teamTwoCardPoints: (json['teamTwoCardPoints'] as num).toInt(),
        teamOneBonusPoints: (json['teamOneBonusPoints'] as num).toInt(),
        teamTwoBonusPoints: (json['teamTwoBonusPoints'] as num).toInt(),
        finishOrder: decodeStringList(json['finishOrder']),
        roundEndType: json['roundEndType'] as String,
      );

  Map<String, dynamic> toJson() => {
    'roundNumber': roundNumber,
    'teamOnePoints': teamOnePoints,
    'teamTwoPoints': teamTwoPoints,
    'teamOneCardPoints': teamOneCardPoints,
    'teamTwoCardPoints': teamTwoCardPoints,
    'teamOneBonusPoints': teamOneBonusPoints,
    'teamTwoBonusPoints': teamTwoBonusPoints,
    'finishOrder': finishOrder,
    'roundEndType': roundEndType,
  };

  RoundScore toDomain() => RoundScore(
    roundNumber: roundNumber,
    teamOnePoints: teamOnePoints,
    teamTwoPoints: teamTwoPoints,
    teamOneCardPoints: teamOneCardPoints,
    teamTwoCardPoints: teamTwoCardPoints,
    teamOneBonusPoints: teamOneBonusPoints,
    teamTwoBonusPoints: teamTwoBonusPoints,
    finishOrder: finishOrder,
    roundEndType: enumByName(RoundEndType.values, roundEndType),
  );
}
