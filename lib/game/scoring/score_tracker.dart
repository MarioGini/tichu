import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/scoring/score_data.dart';
import 'package:tichu/game/turn/tichu_data.dart';

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
    final int? roundNumber,
    final int? teamOneTotal,
    final int? teamTwoTotal,
    final int? teamOneRound,
    final int? teamTwoRound,
    final Map<String, int>? playerRoundPoints,
    final bool? roundComplete,
    final int? targetScore,
    final bool? gameComplete,
    final Object? winningTeam = _unset,
    final List<String>? finishOrder,
    final List<RoundScore>? rounds,
    final Map<String, TichuCall>? tichuCalls,
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

  factory ScoreState.initial({final int targetScore = 1000}) => ScoreState(
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

abstract class ScoreTracker {
  ScoreState get state;

  void startNewRound(final List<GamePlayer> players);

  void recordTrick(final String winnerId, final List<Card> cards);

  void recordPlayerFinished(final String playerId, final List<Card> remainingHand);

  void recordTichuCall(final String playerId, {required final bool isGrand});

  void finalizeRound(final Map<String, List<Card>> hands);
}

class LocalScoreTracker implements ScoreTracker {
  ScoreState _state;
  final Map<String, List<Card>> _capturedCards = {};
  final Map<String, List<Card>> _remainingHands = {};
  final List<String> _finishOrder = [];
  final Map<String, TichuCall> _tichuCalls = {};
  final Map<String, int> _playerSeats = {};

  LocalScoreTracker({final int targetScore = 1000})
    : _state = ScoreState.initial(targetScore: targetScore);

  @override
  ScoreState get state => _state;

  @override
  void startNewRound(final List<GamePlayer> players) {
    _capturedCards
      ..clear()
      ..addEntries(players.map((final p) => MapEntry(p.id, <Card>[])));
    _remainingHands.clear();
    _finishOrder.clear();
    _tichuCalls.clear();
    _playerSeats
      ..clear()
      ..addEntries(players.map((final p) => MapEntry(p.id, p.seat)));

    _state = _state.copyWith(
      roundNumber:
          _state.roundComplete ? _state.roundNumber + 1 : _state.roundNumber,
      roundComplete: false,
      teamOneRound: 0,
      teamTwoRound: 0,
      playerRoundPoints: {for (final p in players) p.id: 0},
      gameComplete: false,
      winningTeam: null,
      finishOrder: const [],
      tichuCalls: const {},
    );
  }

  @override
  void recordTrick(final String winnerId, final List<Card> cards) {
    if (cards.isEmpty) return;
    final captured = _capturedCards[winnerId];
    if (captured == null) return;
    captured.addAll(cards);
    final delta = pointsForCards(cards);
    final roundPoints = {..._state.playerRoundPoints};
    roundPoints[winnerId] = (roundPoints[winnerId] ?? 0) + delta;
    _state = _state.copyWith(
      teamOneRound:
          _state.teamOneRound + (_isTeamOne(winnerId) ? delta : 0),
      teamTwoRound:
          _state.teamTwoRound + (_isTeamOne(winnerId) ? 0 : delta),
      playerRoundPoints: roundPoints,
    );
  }

  @override
  void recordPlayerFinished(final String playerId, final List<Card> remainingHand) {
    if (_finishOrder.contains(playerId)) return;
    _finishOrder.add(playerId);
    _remainingHands[playerId] = List<Card>.from(remainingHand);
    _state = _state.copyWith(finishOrder: List<String>.from(_finishOrder));
  }

  @override
  void recordTichuCall(final String playerId, {required final bool isGrand}) {
    _tichuCalls[playerId] = isGrand ? TichuCall.grandTichu : TichuCall.tichu;
    _state = _state.copyWith(
      tichuCalls: Map<String, TichuCall>.from(_tichuCalls),
    );
  }

  @override
  void finalizeRound(final Map<String, List<Card>> hands) {
    if (_state.roundComplete) return;

    // Fill in any unfinished players at the end.
    _finishOrder.addAll(
      _playerSeats.keys.where((final id) => !_finishOrder.contains(id)),
    );

    final isMatch =
        _finishOrder.length >= 2 &&
        _isTeamOne(_finishOrder[0]) == _isTeamOne(_finishOrder[1]);

    final (teamOneCard, teamTwoCard) = isMatch
        ? (0, 0)
        : _computeNormalCardPoints(hands);
    final matchWinnerIsTeamOne =
        isMatch && _isTeamOne(_finishOrder[0]);
    var teamOneRound = isMatch ? (matchWinnerIsTeamOne ? 200 : 0) : teamOneCard;
    var teamTwoRound = isMatch ? (matchWinnerIsTeamOne ? 0 : 200) : teamTwoCard;

    final (bonusOne, bonusTwo) = _computeTichuBonuses();
    teamOneRound += bonusOne;
    teamTwoRound += bonusTwo;

    final newTeamOneTotal = _state.teamOneTotal + teamOneRound;
    final newTeamTwoTotal = _state.teamTwoTotal + teamTwoRound;
    final gameComplete =
        newTeamOneTotal >= _state.targetScore ||
        newTeamTwoTotal >= _state.targetScore;

    _state = _state.copyWith(
      teamOneRound: teamOneRound,
      teamTwoRound: teamTwoRound,
      teamOneTotal: newTeamOneTotal,
      teamTwoTotal: newTeamTwoTotal,
      rounds: [
        ..._state.rounds,
        RoundScore(
          roundNumber: _state.roundNumber,
          teamOnePoints: teamOneRound,
          teamTwoPoints: teamTwoRound,
          teamOneCardPoints: isMatch ? 0 : teamOneCard,
          teamTwoCardPoints: isMatch ? 0 : teamTwoCard,
          teamOneBonusPoints: bonusOne,
          teamTwoBonusPoints: bonusTwo,
          finishOrder: List<String>.from(_finishOrder),
          roundEndType: isMatch ? RoundEndType.match : RoundEndType.normal,
        ),
      ],
      roundComplete: true,
      gameComplete: gameComplete,
      winningTeam: gameComplete
          ? (newTeamOneTotal == newTeamTwoTotal
                ? null
                : (newTeamOneTotal > newTeamTwoTotal ? 0 : 1))
          : null,
      finishOrder: List<String>.from(_finishOrder),
    );
  }

  /// Sums card points per team for a normal (non-match) round.
  /// Last finisher's tricks go to opposing team; last finisher's remaining
  /// hand goes to first finisher's team.
  (int, int) _computeNormalCardPoints(final Map<String, List<Card>> hands) {
    final first = _finishOrder.first;
    final last = _finishOrder.last;
    var t1 = 0;
    var t2 = 0;

    for (final MapEntry(:key, :value) in _capturedCards.entries) {
      final pts = pointsForCards(value);
      if (key == last) {
        // Last finisher's tricks go to opposing team.
        _isTeamOne(key) ? t2 += pts : t1 += pts;
      } else {
        _isTeamOne(key) ? t1 += pts : t2 += pts;
      }
    }

    // Last finisher's remaining hand goes to first finisher's team.
    final handPts = pointsForCards(hands[last] ?? const <Card>[]);
    _isTeamOne(first) ? t1 += handPts : t2 += handPts;

    return (t1, t2);
  }

  (int, int) _computeTichuBonuses() {
    if (_finishOrder.isEmpty) return (0, 0);
    final firstId = _finishOrder.first;
    var t1 = 0;
    var t2 = 0;

    for (final MapEntry(:key, :value) in _tichuCalls.entries) {
      if (value == TichuCall.none) continue;
      final won = key == firstId;
      final points = value == TichuCall.grandTichu ? 200 : 100;
      final delta = won ? points : -points;
      _isTeamOne(key) ? t1 += delta : t2 += delta;
    }
    return (t1, t2);
  }

  bool _isTeamOne(final String playerId) {
    final seat = _playerSeats[playerId] ?? 0;
    return seat.isEven;
  }
}
