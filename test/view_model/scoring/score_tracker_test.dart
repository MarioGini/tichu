import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/services/game_backend.dart';
import 'package:tichu/view_model/scoring/score_data.dart';
import 'package:tichu/view_model/scoring/score_tracker.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';

const _playerOneId = 'p1';
const _playerTwoId = 'p2';
const _playerThreeId = 'p3';
const _playerFourId = 'p4';

final _players = <GamePlayer>[
  const GamePlayer(id: _playerOneId, name: 'P1', seat: 0, type: PlayerType.ai),
  const GamePlayer(id: _playerTwoId, name: 'P2', seat: 1, type: PlayerType.ai),
  const GamePlayer(
    id: _playerThreeId,
    name: 'P3',
    seat: 2,
    type: PlayerType.ai,
  ),
  const GamePlayer(id: _playerFourId, name: 'P4', seat: 3, type: PlayerType.ai),
];

Card _card(CardFace face, CardColor color) => Card(face, color);

Map<String, List<Card>> _handsWithLast(String lastId, List<Card> lastHand) {
  return {
    _playerOneId: const <Card>[],
    _playerTwoId: const <Card>[],
    _playerThreeId: const <Card>[],
    _playerFourId: const <Card>[],
    lastId: lastHand,
  };
}

void main() {
  group('score data', () {
    test('pointsForCard returns correct values', () {
      expect(pointsForCard(_card(CardFace.five, CardColor.red)), 5);
      expect(pointsForCard(_card(CardFace.ten, CardColor.black)), 10);
      expect(pointsForCard(_card(CardFace.king, CardColor.green)), 10);
      expect(pointsForCard(_card(CardFace.dragon, CardColor.special)), 25);
      expect(pointsForCard(_card(CardFace.phoenix, CardColor.special)), -25);
      expect(pointsForCard(_card(CardFace.ace, CardColor.blue)), 0);
    });

    test('pointsForCards sums correctly', () {
      final cards = [
        _card(CardFace.ten, CardColor.red),
        _card(CardFace.five, CardColor.blue),
        _card(CardFace.phoenix, CardColor.special),
      ];
      expect(pointsForCards(cards), -10);
    });
  });

  group('LocalScoreTracker', () {
    late LocalScoreTracker tracker;

    setUp(() {
      tracker = LocalScoreTracker();
      tracker.startNewRound(_players);
    });

    test('scores regular round with last hand transfer and last captures', () {
      tracker.recordTrick(_playerOneId, [
        _card(CardFace.ten, CardColor.red),
        _card(CardFace.five, CardColor.blue),
      ]);
      tracker.recordTrick(_playerTwoId, [
        _card(CardFace.dragon, CardColor.special),
      ]);
      tracker.recordTrick(_playerThreeId, [
        _card(CardFace.king, CardColor.green),
      ]);
      tracker.recordTrick(_playerFourId, [
        _card(CardFace.phoenix, CardColor.special),
        _card(CardFace.ten, CardColor.black),
      ]);

      tracker.recordPlayerFinished(_playerOneId, const <Card>[]);
      tracker.recordPlayerFinished(_playerTwoId, const <Card>[]);
      tracker.recordPlayerFinished(_playerThreeId, const <Card>[]);
      tracker.recordPlayerFinished(_playerFourId, const <Card>[]);

      tracker.finalizeRound(
        _handsWithLast(_playerFourId, [
          _card(CardFace.five, CardColor.red),
          _card(CardFace.five, CardColor.green),
        ]),
      );

      expect(tracker.state.roundComplete, true);
      expect(tracker.state.teamOneRound, 20);
      expect(tracker.state.teamTwoRound, 25);
      expect(tracker.state.teamOneTotal, 20);
      expect(tracker.state.teamTwoTotal, 25);
      expect(tracker.state.rounds, hasLength(1));
      expect(tracker.state.rounds.last.teamOneCardPoints, 20);
      expect(tracker.state.rounds.last.teamTwoCardPoints, 25);
    });

    test('applies tichu and grand tichu bonuses', () {
      tracker.recordPlayerFinished(_playerOneId, const <Card>[]);
      tracker.recordPlayerFinished(_playerTwoId, const <Card>[]);
      tracker.recordPlayerFinished(_playerThreeId, const <Card>[]);
      tracker.recordPlayerFinished(_playerFourId, const <Card>[]);

      tracker.recordTichuCall(_playerOneId, isGrand: false);
      tracker.recordTichuCall(_playerTwoId, isGrand: true);

      tracker.finalizeRound(_handsWithLast(_playerFourId, const <Card>[]));

      expect(tracker.state.teamOneRound, 100);
      expect(tracker.state.teamTwoRound, -200);
      expect(tracker.state.rounds.last.teamOneBonusPoints, 100);
      expect(tracker.state.rounds.last.teamTwoBonusPoints, -200);
    });

    test('double win overrides card points', () {
      tracker.recordTrick(_playerOneId, [_card(CardFace.ten, CardColor.red)]);
      tracker.recordTrick(_playerTwoId, [
        _card(CardFace.king, CardColor.black),
      ]);
      tracker.recordTrick(_playerThreeId, [
        _card(CardFace.five, CardColor.blue),
      ]);
      tracker.recordTrick(_playerFourId, [
        _card(CardFace.dragon, CardColor.special),
      ]);

      tracker.recordPlayerFinished(_playerOneId, const <Card>[]);
      tracker.recordPlayerFinished(_playerThreeId, const <Card>[]);
      tracker.recordPlayerFinished(_playerTwoId, const <Card>[]);
      tracker.recordPlayerFinished(_playerFourId, const <Card>[]);

      tracker.finalizeRound(_handsWithLast(_playerFourId, const <Card>[]));

      expect(tracker.state.teamOneRound, 200);
      expect(tracker.state.teamTwoRound, 0);
      expect(tracker.state.rounds.last.teamOneCardPoints, 40);
      expect(tracker.state.rounds.last.teamTwoCardPoints, 10);
    });

    test('finalizeRound appends missing finishers', () {
      tracker.recordPlayerFinished(_playerOneId, const <Card>[]);
      tracker.recordPlayerFinished(_playerTwoId, const <Card>[]);

      tracker.finalizeRound(_handsWithLast(_playerFourId, const <Card>[]));

      expect(tracker.state.finishOrder, [
        _playerOneId,
        _playerTwoId,
        _playerThreeId,
        _playerFourId,
      ]);
    });
  });
}
