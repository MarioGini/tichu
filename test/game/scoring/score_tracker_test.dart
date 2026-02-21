import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

const _playerOneId = 'p1';
const _playerTwoId = 'p2';
const _playerThreeId = 'p3';
const _playerFourId = 'p4';

final _players = <GamePlayer>[
  const GamePlayer(
    id: _playerOneId,
    name: 'P1',
    seat: 0,
    type: PlayerType.automated,
  ),
  const GamePlayer(
    id: _playerTwoId,
    name: 'P2',
    seat: 1,
    type: PlayerType.automated,
  ),
  const GamePlayer(
    id: _playerThreeId,
    name: 'P3',
    seat: 2,
    type: PlayerType.automated,
  ),
  const GamePlayer(
    id: _playerFourId,
    name: 'P4',
    seat: 3,
    type: PlayerType.automated,
  ),
];

Card _card(final CardFace face, final CardColor color) => Card(face, color);

Map<String, List<Card>> _handsWithLast(
  final String lastId,
  final List<Card> lastHand,
) => {
  _playerOneId: const <Card>[],
  _playerTwoId: const <Card>[],
  _playerThreeId: const <Card>[],
  _playerFourId: const <Card>[],
  lastId: lastHand,
};

void main() {
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
      expect(tracker.state.rounds.last.roundEndType, RoundEndType.normal);
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

    test('double win (match) uses fixed score without card counting', () {
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
      expect(tracker.state.rounds.last.teamOneCardPoints, 0);
      expect(tracker.state.rounds.last.teamTwoCardPoints, 0);
      expect(tracker.state.rounds.last.roundEndType, RoundEndType.match);
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

    test('recordTrick ignores unknown winner and empty trick', () {
      tracker.recordTrick('unknown', [_card(CardFace.ten, CardColor.red)]);
      tracker.recordTrick(_playerOneId, const <Card>[]);

      expect(tracker.state.teamOneRound, 0);
      expect(tracker.state.teamTwoRound, 0);
    });

    test('recordPlayerFinished is idempotent', () {
      tracker.recordPlayerFinished(_playerOneId, const <Card>[]);
      tracker.recordPlayerFinished(_playerOneId, const <Card>[]);

      expect(tracker.state.finishOrder, [_playerOneId]);
    });

    test('finalizeRound is idempotent after completion', () {
      tracker.recordPlayerFinished(_playerOneId, const <Card>[]);
      tracker.recordPlayerFinished(_playerThreeId, const <Card>[]);
      tracker.recordPlayerFinished(_playerTwoId, const <Card>[]);
      tracker.recordPlayerFinished(_playerFourId, const <Card>[]);

      tracker.finalizeRound(_handsWithLast(_playerFourId, const <Card>[]));
      final firstTotalOne = tracker.state.teamOneTotal;
      final firstTotalTwo = tracker.state.teamTwoTotal;

      tracker.finalizeRound(_handsWithLast(_playerFourId, const <Card>[]));
      expect(tracker.state.teamOneTotal, firstTotalOne);
      expect(tracker.state.teamTwoTotal, firstTotalTwo);
      expect(tracker.state.rounds, hasLength(1));
    });

    test('round advances on startNewRound after completion', () {
      tracker.recordPlayerFinished(_playerOneId, const <Card>[]);
      tracker.recordPlayerFinished(_playerThreeId, const <Card>[]);
      tracker.recordPlayerFinished(_playerTwoId, const <Card>[]);
      tracker.recordPlayerFinished(_playerFourId, const <Card>[]);
      tracker.finalizeRound(_handsWithLast(_playerFourId, const <Card>[]));

      tracker.startNewRound(_players);

      expect(tracker.state.roundNumber, 2);
      expect(tracker.state.roundComplete, isFalse);
      expect(tracker.state.teamOneRound, 0);
      expect(tracker.state.teamTwoRound, 0);
      expect(tracker.state.tichuCalls, isEmpty);
    });

    test('winningTeam is set when one team crosses target score', () {
      final winTracker = LocalScoreTracker(targetScore: 200);
      winTracker.startNewRound(_players);

      winTracker.recordPlayerFinished(_playerOneId, const <Card>[]);
      winTracker.recordPlayerFinished(_playerThreeId, const <Card>[]);
      winTracker.recordPlayerFinished(_playerTwoId, const <Card>[]);
      winTracker.recordPlayerFinished(_playerFourId, const <Card>[]);

      winTracker.finalizeRound(_handsWithLast(_playerFourId, const <Card>[]));

      expect(winTracker.state.gameComplete, isTrue);
      expect(winTracker.state.teamOneTotal, 200);
      expect(winTracker.state.winningTeam, 0);
    });

    test('losing tichu call applies negative bonus to caller team', () {
      tracker.recordPlayerFinished(_playerTwoId, const <Card>[]);
      tracker.recordPlayerFinished(_playerOneId, const <Card>[]);
      tracker.recordPlayerFinished(_playerThreeId, const <Card>[]);
      tracker.recordPlayerFinished(_playerFourId, const <Card>[]);

      tracker.recordTichuCall(_playerOneId, isGrand: false);
      tracker.finalizeRound(_handsWithLast(_playerFourId, const <Card>[]));

      expect(tracker.state.rounds.last.teamOneBonusPoints, -100);
      expect(
        tracker.state.teamOneRound,
        lessThan(tracker.state.rounds.last.teamOneCardPoints),
      );
    });

    test('only first finisher call succeeds even on winning team', () {
      tracker.recordPlayerFinished(_playerOneId, const <Card>[]);
      tracker.recordPlayerFinished(_playerTwoId, const <Card>[]);
      tracker.recordPlayerFinished(_playerThreeId, const <Card>[]);
      tracker.recordPlayerFinished(_playerFourId, const <Card>[]);

      tracker.recordTichuCall(_playerOneId, isGrand: false);
      tracker.recordTichuCall(_playerThreeId, isGrand: true);

      tracker.finalizeRound(_handsWithLast(_playerFourId, const <Card>[]));

      expect(tracker.state.rounds.last.teamOneCardPoints, 0);
      expect(tracker.state.rounds.last.teamOneBonusPoints, -100);
      expect(tracker.state.rounds.last.teamOnePoints, -100);
      expect(tracker.state.rounds.last.teamTwoBonusPoints, 0);
    });

    test('double win with missed tichu by second finisher nets +100', () {
      tracker.recordPlayerFinished(_playerThreeId, const <Card>[]);
      tracker.recordPlayerFinished(_playerOneId, const <Card>[]);
      tracker.recordPlayerFinished(_playerTwoId, const <Card>[]);
      tracker.recordPlayerFinished(_playerFourId, const <Card>[]);

      tracker.recordTichuCall(_playerOneId, isGrand: false);

      tracker.finalizeRound(_handsWithLast(_playerFourId, const <Card>[]));

      expect(tracker.state.rounds.last.teamOneCardPoints, 0);
      expect(tracker.state.rounds.last.teamOneBonusPoints, -100);
      expect(tracker.state.teamOneRound, 100);
      expect(tracker.state.teamTwoRound, 0);
    });

    test('all calls on losing team are negative and stack', () {
      tracker.recordPlayerFinished(_playerOneId, const <Card>[]);
      tracker.recordPlayerFinished(_playerTwoId, const <Card>[]);
      tracker.recordPlayerFinished(_playerThreeId, const <Card>[]);
      tracker.recordPlayerFinished(_playerFourId, const <Card>[]);

      tracker.recordTichuCall(_playerTwoId, isGrand: false);
      tracker.recordTichuCall(_playerFourId, isGrand: true);

      tracker.finalizeRound(_handsWithLast(_playerFourId, const <Card>[]));

      expect(tracker.state.rounds.last.teamTwoCardPoints, 0);
      expect(tracker.state.rounds.last.teamTwoBonusPoints, -300);
      expect(tracker.state.rounds.last.teamTwoPoints, -300);
      expect(tracker.state.rounds.last.teamOneBonusPoints, 0);
    });
  });
}
