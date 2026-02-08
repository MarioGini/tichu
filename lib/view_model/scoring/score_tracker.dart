import 'package:tichu/services/game_backend.dart';
import 'package:tichu/view_model/scoring/score_data.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';

enum TichuCall { none, tichu, grandTichu }

class RoundScore {
  final int roundNumber;
  final int teamOnePoints;
  final int teamTwoPoints;
  final int teamOneCardPoints;
  final int teamTwoCardPoints;
  final int teamOneBonusPoints;
  final int teamTwoBonusPoints;
  final List<String> finishOrder;

  const RoundScore({
    required this.roundNumber,
    required this.teamOnePoints,
    required this.teamTwoPoints,
    required this.teamOneCardPoints,
    required this.teamTwoCardPoints,
    required this.teamOneBonusPoints,
    required this.teamTwoBonusPoints,
    required this.finishOrder,
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
  }) {
    return ScoreState(
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
  }

  factory ScoreState.initial({int targetScore = 1000}) {
    return ScoreState(
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
}

abstract class ScoreTracker {
  ScoreState get state;

  void startNewRound(List<GamePlayer> players);

  void recordTrick(String winnerId, List<Card> cards);

  void recordPlayerFinished(String playerId, List<Card> remainingHand);

  void recordTichuCall(String playerId, {required bool isGrand});

  void finalizeRound(Map<String, List<Card>> hands);
}

class LocalScoreTracker implements ScoreTracker {
  ScoreState _state;
  final Map<String, List<Card>> _capturedCards = {};
  final Map<String, List<Card>> _remainingHands = {};
  final List<String> _finishOrder = [];
  final Map<String, TichuCall> _tichuCalls = {};
  final Map<String, int> _playerSeats = {};

  LocalScoreTracker({int targetScore = 1000})
    : _state = ScoreState.initial(targetScore: targetScore);

  @override
  ScoreState get state => _state;

  @override
  void startNewRound(List<GamePlayer> players) {
    final nextRoundNumber = _state.roundComplete
        ? _state.roundNumber + 1
        : _state.roundNumber;
    _capturedCards
      ..clear()
      ..addEntries(players.map((player) => MapEntry(player.id, <Card>[])));
    _remainingHands.clear();
    _finishOrder.clear();
    _tichuCalls.clear();
    _playerSeats
      ..clear()
      ..addEntries(players.map((player) => MapEntry(player.id, player.seat)));

    _state = _state.copyWith(
      roundNumber: nextRoundNumber,
      roundComplete: false,
      teamOneRound: 0,
      teamTwoRound: 0,
      playerRoundPoints: {for (final player in players) player.id: 0},
      gameComplete: false,
      winningTeam: null,
      finishOrder: const [],
      tichuCalls: const {},
    );
  }

  @override
  void recordTrick(String winnerId, List<Card> cards) {
    if (cards.isEmpty) return;
    final captured = _capturedCards[winnerId];
    if (captured == null) return;
    captured.addAll(cards);
    final delta = pointsForCards(cards);
    final roundPoints = Map<String, int>.from(_state.playerRoundPoints);
    roundPoints[winnerId] = (roundPoints[winnerId] ?? 0) + delta;
    if (_isTeamOne(winnerId)) {
      _state = _state.copyWith(
        teamOneRound: _state.teamOneRound + delta,
        playerRoundPoints: roundPoints,
      );
    } else {
      _state = _state.copyWith(
        teamTwoRound: _state.teamTwoRound + delta,
        playerRoundPoints: roundPoints,
      );
    }
  }

  @override
  void recordPlayerFinished(String playerId, List<Card> remainingHand) {
    if (_finishOrder.contains(playerId)) return;
    _finishOrder.add(playerId);
    _remainingHands[playerId] = List<Card>.from(remainingHand);
    _state = _state.copyWith(finishOrder: List<String>.from(_finishOrder));
  }

  @override
  void recordTichuCall(String playerId, {required bool isGrand}) {
    _tichuCalls[playerId] = isGrand ? TichuCall.grandTichu : TichuCall.tichu;
    _state = _state.copyWith(
      tichuCalls: Map<String, TichuCall>.from(_tichuCalls),
    );
  }

  @override
  void finalizeRound(Map<String, List<Card>> hands) {
    if (_state.roundComplete) return;

    if (_finishOrder.length < _playerSeats.length) {
      final remainingPlayers = _playerSeats.keys
          .where((playerId) => !_finishOrder.contains(playerId))
          .toList();
      _finishOrder.addAll(remainingPlayers);
    }

    final firstFinisher = _finishOrder.first;
    final lastFinisher = _finishOrder.last;

    final lastHand = hands[lastFinisher] ?? const <Card>[];

    final teamOneCards = <Card>[];
    final teamTwoCards = <Card>[];

    for (final entry in _capturedCards.entries) {
      final playerId = entry.key;
      final cards = entry.value;
      if (playerId == lastFinisher) {
        continue;
      }
      if (_isTeamOne(playerId)) {
        teamOneCards.addAll(cards);
      } else {
        teamTwoCards.addAll(cards);
      }
    }

    if (_isTeamOne(lastFinisher)) {
      teamTwoCards.addAll(_capturedCards[lastFinisher] ?? const <Card>[]);
    } else {
      teamOneCards.addAll(_capturedCards[lastFinisher] ?? const <Card>[]);
    }

    if (_isTeamOne(firstFinisher)) {
      teamOneCards.addAll(lastHand);
    } else {
      teamTwoCards.addAll(lastHand);
    }

    final teamOneCardPoints = pointsForCards(teamOneCards);
    final teamTwoCardPoints = pointsForCards(teamTwoCards);

    var teamOneRound = teamOneCardPoints;
    var teamTwoRound = teamTwoCardPoints;

    final doubleWin =
        _isTeamOne(_finishOrder[0]) == _isTeamOne(_finishOrder[1]);

    if (doubleWin) {
      if (_isTeamOne(_finishOrder[0])) {
        teamOneRound = 200;
        teamTwoRound = 0;
      } else {
        teamOneRound = 0;
        teamTwoRound = 200;
      }
    }

    final tichuBonuses = _computeTichuBonuses();
    teamOneRound += tichuBonuses.$1;
    teamTwoRound += tichuBonuses.$2;

    final roundScore = RoundScore(
      roundNumber: _state.roundNumber,
      teamOnePoints: teamOneRound,
      teamTwoPoints: teamTwoRound,
      teamOneCardPoints: teamOneCardPoints,
      teamTwoCardPoints: teamTwoCardPoints,
      teamOneBonusPoints: tichuBonuses.$1,
      teamTwoBonusPoints: tichuBonuses.$2,
      finishOrder: List<String>.from(_finishOrder),
    );

    final updatedTeamOneTotal = _state.teamOneTotal + teamOneRound;
    final updatedTeamTwoTotal = _state.teamTwoTotal + teamTwoRound;
    final gameComplete =
        updatedTeamOneTotal >= _state.targetScore ||
        updatedTeamTwoTotal >= _state.targetScore;
    final int? winningTeam = gameComplete
        ? (updatedTeamOneTotal == updatedTeamTwoTotal
              ? null
              : (updatedTeamOneTotal > updatedTeamTwoTotal ? 0 : 1))
        : null;

    _state = _state.copyWith(
      teamOneRound: teamOneRound,
      teamTwoRound: teamTwoRound,
      teamOneTotal: updatedTeamOneTotal,
      teamTwoTotal: updatedTeamTwoTotal,
      rounds: [..._state.rounds, roundScore],
      roundComplete: true,
      gameComplete: gameComplete,
      winningTeam: winningTeam,
      finishOrder: List<String>.from(_finishOrder),
    );
  }

  (int, int) _computeTichuBonuses() {
    var teamOneBonus = 0;
    var teamTwoBonus = 0;

    if (_finishOrder.isEmpty) return (0, 0);

    final winner = _finishOrder.first;

    for (final entry in _tichuCalls.entries) {
      final playerId = entry.key;
      final call = entry.value;
      if (call == TichuCall.none) continue;

      final isWinner = playerId == winner;
      final delta = call == TichuCall.grandTichu ? 200 : 100;
      final scoreDelta = isWinner ? delta : -delta;

      if (_isTeamOne(playerId)) {
        teamOneBonus += scoreDelta;
      } else {
        teamTwoBonus += scoreDelta;
      }
    }

    return (teamOneBonus, teamTwoBonus);
  }

  bool _isTeamOne(String playerId) {
    final seat = _playerSeats[playerId] ?? 0;
    return seat.isEven;
  }
}
