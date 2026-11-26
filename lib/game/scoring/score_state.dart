enum TichuCall { none, tichu, grandTichu }

enum RoundEndType { normal, match }

class RoundScore {
  final int roundNumber;
  final int teamOnePoints;
  final int teamTwoPoints;
  final int teamOneCardPoints;
  final int teamTwoCardPoints;
  final int teamOneBonusPoints;
  final int teamTwoBonusPoints;
  final List<String> finishOrder;
  final RoundEndType roundEndType;

  bool get isMatch => roundEndType == RoundEndType.match;

  const RoundScore({
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
}

class ScoreState {
  static const Object _unset = Object();

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
  final List<RoundScore> rounds;
  final Map<String, TichuCall> tichuCalls;

  const ScoreState({
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

  ScoreState copyWith({
    int? roundNumber,
    int? teamOneTotal,
    int? teamTwoTotal,
    int? teamOneRound,
    int? teamTwoRound,
    Map<String, int>? playerRoundPoints,
    bool? roundComplete,
    int? targetScore,
    bool? gameComplete,
    Object? winningTeam = _unset,
    List<String>? finishOrder,
    List<RoundScore>? rounds,
    Map<String, TichuCall>? tichuCalls,
  }) => ScoreState(
    roundNumber: roundNumber ?? this.roundNumber,
    teamOneTotal: teamOneTotal ?? this.teamOneTotal,
    teamTwoTotal: teamTwoTotal ?? this.teamTwoTotal,
    teamOneRound: teamOneRound ?? this.teamOneRound,
    teamTwoRound: teamTwoRound ?? this.teamTwoRound,
    playerRoundPoints: playerRoundPoints ?? this.playerRoundPoints,
    roundComplete: roundComplete ?? this.roundComplete,
    targetScore: targetScore ?? this.targetScore,
    gameComplete: gameComplete ?? this.gameComplete,
    winningTeam: identical(winningTeam, _unset)
        ? this.winningTeam
        : winningTeam as int?,
    finishOrder: finishOrder ?? this.finishOrder,
    rounds: rounds ?? this.rounds,
    tichuCalls: tichuCalls ?? this.tichuCalls,
  );

  factory ScoreState.initial({int targetScore = 1000}) => ScoreState(
    roundNumber: 1,
    teamOneTotal: 0,
    teamTwoTotal: 0,
    teamOneRound: 0,
    teamTwoRound: 0,
    playerRoundPoints: const {},
    roundComplete: false,
    targetScore: targetScore,
    gameComplete: false,
    winningTeam: null,
    finishOrder: [],
    rounds: [],
    tichuCalls: {},
  );
}
