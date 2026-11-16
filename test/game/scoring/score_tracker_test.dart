import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'score_test_fixtures.dart';

void main() {
  group('LocalScoreTracker', () {
    late LocalScoreTracker tracker;

    setUp(() {
      tracker = LocalScoreTracker();
      tracker.startNewRound(players);
    });

    test('scores regular round with last hand transfer and last captures', () {
      tracker.recordTrick(playerOneId, [
        fxCard(CardFace.ten, CardColor.red),
        fxCard(CardFace.five, CardColor.blue),
      ]);
      tracker.recordTrick(playerTwoId, [
        fxCard(CardFace.dragon, CardColor.special),
      ]);
      tracker.recordTrick(playerThreeId, [
        fxCard(CardFace.king, CardColor.green),
      ]);
      tracker.recordTrick(playerFourId, [
        fxCard(CardFace.phoenix, CardColor.special),
        fxCard(CardFace.ten, CardColor.black),
      ]);

      tracker.recordPlayerFinished(playerOneId, const <Card>[]);
      tracker.recordPlayerFinished(playerTwoId, const <Card>[]);
      tracker.recordPlayerFinished(playerThreeId, const <Card>[]);
      tracker.recordPlayerFinished(playerFourId, const <Card>[]);

      tracker.finalizeRound(
        handsWithLast(playerFourId, [
          fxCard(CardFace.five, CardColor.red),
          fxCard(CardFace.five, CardColor.green),
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

    test("last player is the first player's partner: tricks stay in the team, "
        'hand goes to the opponents', () {
      tracker.recordTrick(playerTwoId, [fxCard(CardFace.ten, CardColor.red)]);
      // P3 (partner of the first-out P1) finishes last with won tricks
      // worth 20 and 15 points still in hand.
      tracker.recordTrick(playerThreeId, [
        fxCard(CardFace.king, CardColor.green),
        fxCard(CardFace.ten, CardColor.black),
      ]);

      tracker.recordPlayerFinished(playerOneId, const <Card>[]);
      tracker.recordPlayerFinished(playerTwoId, const <Card>[]);
      tracker.recordPlayerFinished(playerFourId, const <Card>[]);
      tracker.recordPlayerFinished(playerThreeId, const <Card>[]);

      tracker.finalizeRound(
        handsWithLast(playerThreeId, [
          fxCard(CardFace.ten, CardColor.blue),
          fxCard(CardFace.five, CardColor.green),
        ]),
      );

      // Team one (P1, P3): P3's tricks (20) go to P1.
      expect(tracker.state.teamOneRound, 20);
      // Team two (P2, P4): own trick (10) + P3's hand (15).
      expect(tracker.state.teamTwoRound, 25);
    });

    test('applies tichu and grand tichu bonuses', () {
      tracker.recordPlayerFinished(playerOneId, const <Card>[]);
      tracker.recordPlayerFinished(playerTwoId, const <Card>[]);
      tracker.recordPlayerFinished(playerThreeId, const <Card>[]);
      tracker.recordPlayerFinished(playerFourId, const <Card>[]);

      tracker.recordTichuCall(playerOneId, isGrand: false);
      tracker.recordTichuCall(playerTwoId, isGrand: true);

      tracker.finalizeRound(handsWithLast(playerFourId, const <Card>[]));

      expect(tracker.state.teamOneRound, 100);
      expect(tracker.state.teamTwoRound, -200);
      expect(tracker.state.rounds.last.teamOneBonusPoints, 100);
      expect(tracker.state.rounds.last.teamTwoBonusPoints, -200);
    });

    test('double win (match) uses fixed score without card counting', () {
      tracker.recordTrick(playerOneId, [fxCard(CardFace.ten, CardColor.red)]);
      tracker.recordTrick(playerTwoId, [
        fxCard(CardFace.king, CardColor.black),
      ]);
      tracker.recordTrick(playerThreeId, [
        fxCard(CardFace.five, CardColor.blue),
      ]);
      tracker.recordTrick(playerFourId, [
        fxCard(CardFace.dragon, CardColor.special),
      ]);

      tracker.recordPlayerFinished(playerOneId, const <Card>[]);
      tracker.recordPlayerFinished(playerThreeId, const <Card>[]);
      tracker.recordPlayerFinished(playerTwoId, const <Card>[]);
      tracker.recordPlayerFinished(playerFourId, const <Card>[]);

      tracker.finalizeRound(handsWithLast(playerFourId, const <Card>[]));

      expect(tracker.state.teamOneRound, 200);
      expect(tracker.state.teamTwoRound, 0);
      expect(tracker.state.rounds.last.teamOneCardPoints, 0);
      expect(tracker.state.rounds.last.teamTwoCardPoints, 0);
      expect(tracker.state.rounds.last.roundEndType, RoundEndType.match);
    });

    test('finalizeRound appends missing finishers', () {
      tracker.recordPlayerFinished(playerOneId, const <Card>[]);
      tracker.recordPlayerFinished(playerTwoId, const <Card>[]);

      tracker.finalizeRound(handsWithLast(playerFourId, const <Card>[]));

      expect(tracker.state.finishOrder, [
        playerOneId,
        playerTwoId,
        playerThreeId,
        playerFourId,
      ]);
    });

    test('recordTrick ignores unknown winner and empty trick', () {
      tracker.recordTrick('unknown', [fxCard(CardFace.ten, CardColor.red)]);
      tracker.recordTrick(playerOneId, const <Card>[]);

      expect(tracker.state.teamOneRound, 0);
      expect(tracker.state.teamTwoRound, 0);
    });

    test('recordPlayerFinished is idempotent', () {
      tracker.recordPlayerFinished(playerOneId, const <Card>[]);
      tracker.recordPlayerFinished(playerOneId, const <Card>[]);

      expect(tracker.state.finishOrder, [playerOneId]);
    });

    test('finalizeRound is idempotent after completion', () {
      tracker.recordPlayerFinished(playerOneId, const <Card>[]);
      tracker.recordPlayerFinished(playerThreeId, const <Card>[]);
      tracker.recordPlayerFinished(playerTwoId, const <Card>[]);
      tracker.recordPlayerFinished(playerFourId, const <Card>[]);

      tracker.finalizeRound(handsWithLast(playerFourId, const <Card>[]));
      final firstTotalOne = tracker.state.teamOneTotal;
      final firstTotalTwo = tracker.state.teamTwoTotal;

      tracker.finalizeRound(handsWithLast(playerFourId, const <Card>[]));
      expect(tracker.state.teamOneTotal, firstTotalOne);
      expect(tracker.state.teamTwoTotal, firstTotalTwo);
      expect(tracker.state.rounds, hasLength(1));
    });

    test('round advances on startNewRound after completion', () {
      tracker.recordPlayerFinished(playerOneId, const <Card>[]);
      tracker.recordPlayerFinished(playerThreeId, const <Card>[]);
      tracker.recordPlayerFinished(playerTwoId, const <Card>[]);
      tracker.recordPlayerFinished(playerFourId, const <Card>[]);
      tracker.finalizeRound(handsWithLast(playerFourId, const <Card>[]));

      tracker.startNewRound(players);

      expect(tracker.state.roundNumber, 2);
      expect(tracker.state.roundComplete, isFalse);
      expect(tracker.state.teamOneRound, 0);
      expect(tracker.state.teamTwoRound, 0);
      expect(tracker.state.tichuCalls, isEmpty);
    });

    test('winningTeam is set when one team crosses target score', () {
      final winTracker = LocalScoreTracker(targetScore: 200);
      winTracker.startNewRound(players);

      winTracker.recordPlayerFinished(playerOneId, const <Card>[]);
      winTracker.recordPlayerFinished(playerThreeId, const <Card>[]);
      winTracker.recordPlayerFinished(playerTwoId, const <Card>[]);
      winTracker.recordPlayerFinished(playerFourId, const <Card>[]);

      winTracker.finalizeRound(handsWithLast(playerFourId, const <Card>[]));

      expect(winTracker.state.gameComplete, isTrue);
      expect(winTracker.state.teamOneTotal, 200);
      expect(winTracker.state.winningTeam, 0);
    });

    test('losing tichu call applies negative bonus to caller team', () {
      tracker.recordPlayerFinished(playerTwoId, const <Card>[]);
      tracker.recordPlayerFinished(playerOneId, const <Card>[]);
      tracker.recordPlayerFinished(playerThreeId, const <Card>[]);
      tracker.recordPlayerFinished(playerFourId, const <Card>[]);

      tracker.recordTichuCall(playerOneId, isGrand: false);
      tracker.finalizeRound(handsWithLast(playerFourId, const <Card>[]));

      expect(tracker.state.rounds.last.teamOneBonusPoints, -100);
      expect(
        tracker.state.teamOneRound,
        lessThan(tracker.state.rounds.last.teamOneCardPoints),
      );
    });

    test('only first finisher call succeeds even on winning team', () {
      tracker.recordPlayerFinished(playerOneId, const <Card>[]);
      tracker.recordPlayerFinished(playerTwoId, const <Card>[]);
      tracker.recordPlayerFinished(playerThreeId, const <Card>[]);
      tracker.recordPlayerFinished(playerFourId, const <Card>[]);

      tracker.recordTichuCall(playerOneId, isGrand: false);
      tracker.recordTichuCall(playerThreeId, isGrand: true);

      tracker.finalizeRound(handsWithLast(playerFourId, const <Card>[]));

      expect(tracker.state.rounds.last.teamOneCardPoints, 0);
      expect(tracker.state.rounds.last.teamOneBonusPoints, -100);
      expect(tracker.state.rounds.last.teamOnePoints, -100);
      expect(tracker.state.rounds.last.teamTwoBonusPoints, 0);
    });

    test('double win with missed tichu by second finisher nets +100', () {
      tracker.recordPlayerFinished(playerThreeId, const <Card>[]);
      tracker.recordPlayerFinished(playerOneId, const <Card>[]);
      tracker.recordPlayerFinished(playerTwoId, const <Card>[]);
      tracker.recordPlayerFinished(playerFourId, const <Card>[]);

      tracker.recordTichuCall(playerOneId, isGrand: false);

      tracker.finalizeRound(handsWithLast(playerFourId, const <Card>[]));

      expect(tracker.state.rounds.last.teamOneCardPoints, 0);
      expect(tracker.state.rounds.last.teamOneBonusPoints, -100);
      expect(tracker.state.teamOneRound, 100);
      expect(tracker.state.teamTwoRound, 0);
    });

    test('all calls on losing team are negative and stack', () {
      tracker.recordPlayerFinished(playerOneId, const <Card>[]);
      tracker.recordPlayerFinished(playerTwoId, const <Card>[]);
      tracker.recordPlayerFinished(playerThreeId, const <Card>[]);
      tracker.recordPlayerFinished(playerFourId, const <Card>[]);

      tracker.recordTichuCall(playerTwoId, isGrand: false);
      tracker.recordTichuCall(playerFourId, isGrand: true);

      tracker.finalizeRound(handsWithLast(playerFourId, const <Card>[]));

      expect(tracker.state.rounds.last.teamTwoCardPoints, 0);
      expect(tracker.state.rounds.last.teamTwoBonusPoints, -300);
      expect(tracker.state.rounds.last.teamTwoPoints, -300);
      expect(tracker.state.rounds.last.teamOneBonusPoints, 0);
    });
  });
}
