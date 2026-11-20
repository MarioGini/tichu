import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/scoring/score_data.dart';
import 'package:tichu/game/scoring/score_state.dart';
import 'package:tichu/game/turn/tichu_data.dart';

export 'package:tichu/game/scoring/score_state.dart';

/// Tracks trick points, finish order and Tichu calls of a match.
class LocalScoreTracker {
  ScoreState _state;
  final Map<String, List<Card>> _capturedCards = {};
  final Map<String, List<Card>> _remainingHands = {};
  final List<String> _finishOrder = [];
  final Map<String, TichuCall> _tichuCalls = {};
  final Map<String, int> _playerSeats = {};

  LocalScoreTracker({final int targetScore = 1000})
    : _state = ScoreState.initial(targetScore: targetScore);

  /// Independent deep copy (for forking a round, e.g. counterfactual
  /// training labels).
  LocalScoreTracker copy() {
    final c = LocalScoreTracker().._state = _state;
    for (final e in _capturedCards.entries) {
      c._capturedCards[e.key] = List<Card>.from(e.value);
    }
    for (final e in _remainingHands.entries) {
      c._remainingHands[e.key] = List<Card>.from(e.value);
    }
    c._finishOrder.addAll(_finishOrder);
    c._tichuCalls.addAll(_tichuCalls);
    c._playerSeats.addAll(_playerSeats);
    return c;
  }

  ScoreState get state => _state;

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
      roundNumber: _state.roundComplete
          ? _state.roundNumber + 1
          : _state.roundNumber,
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

  void recordTrick(final String winnerId, final List<Card> cards) {
    if (cards.isEmpty) return;
    final captured = _capturedCards[winnerId];
    if (captured == null) return;
    captured.addAll(cards);
    final delta = pointsForCards(cards);
    final roundPoints = {..._state.playerRoundPoints};
    roundPoints[winnerId] = (roundPoints[winnerId] ?? 0) + delta;
    _state = _state.copyWith(
      teamOneRound: _state.teamOneRound + (_isTeamOne(winnerId) ? delta : 0),
      teamTwoRound: _state.teamTwoRound + (_isTeamOne(winnerId) ? 0 : delta),
      playerRoundPoints: roundPoints,
    );
  }

  void recordPlayerFinished(
    final String playerId,
    final List<Card> remainingHand,
  ) {
    if (_finishOrder.contains(playerId)) return;
    _finishOrder.add(playerId);
    _remainingHands[playerId] = List<Card>.from(remainingHand);
    _state = _state.copyWith(finishOrder: List<String>.from(_finishOrder));
  }

  void recordTichuCall(final String playerId, {required final bool isGrand}) {
    _tichuCalls[playerId] = isGrand ? TichuCall.grandTichu : TichuCall.tichu;
    _state = _state.copyWith(
      tichuCalls: Map<String, TichuCall>.from(_tichuCalls),
    );
  }

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
    final matchWinnerIsTeamOne = isMatch && _isTeamOne(_finishOrder[0]);
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

  /// Sums card points per team for a normal (non-match) round: the last
  /// finisher's tricks go to the first finisher, the cards left in the last
  /// finisher's hand go to the opposing team.
  (int, int) _computeNormalCardPoints(final Map<String, List<Card>> hands) {
    final first = _finishOrder.first;
    final last = _finishOrder.last;
    var t1 = 0;
    var t2 = 0;

    // Official rule: the last player gives the tricks they won to the
    // player who went out first, and the cards left in their hand to the
    // opposing team. (When the last player is the first player's partner,
    // the tricks stay in the team and the hand goes to the opponents.)
    for (final MapEntry(:key, :value) in _capturedCards.entries) {
      final pts = pointsForCards(value);
      final team = key == last ? first : key;
      _isTeamOne(team) ? t1 += pts : t2 += pts;
    }

    final handPts = pointsForCards(hands[last] ?? const <Card>[]);
    _isTeamOne(last) ? t2 += handPts : t1 += handPts;

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
