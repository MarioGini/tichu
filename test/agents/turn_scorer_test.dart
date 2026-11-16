import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/turn_scorer.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'ai_test_fixtures.dart';

void main() {
  const scorer = TurnScorer();

  group('TurnScorer', () {
    test('spends an ace freely once nothing unseen can beat it', () {
      final ace = Card(CardFace.ace, CardColor.red);
      final hand = [
        ace,
        Card(CardFace.three, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.seven, CardColor.black),
        Card(CardFace.nine, CardColor.red),
        Card(CardFace.jack, CardColor.blue),
        Card(CardFace.queen, CardColor.green),
        Card(CardFace.two, CardColor.green),
        Card(CardFace.four, CardColor.black),
      ];
      final deck = DeckState(
        TichuTurn(TurnType.single, [Card(CardFace.king, CardColor.green)]),
        CardFace.none,
      )..currentWinner = aiTestLeftId;
      final play = TichuTurn(TurnType.single, [ace]);

      double scoreWith(final List<Card> rightHand) => scorer.scoreTurn(
        aiSnapshot(
          myHand: hand,
          deck: deck,
          otherHands: {
            aiTestLeftId: [Card(CardFace.six, CardColor.red)],
            aiTestPartnerId: [Card(CardFace.eight, CardColor.red)],
            aiTestRightId: rightHand,
          },
        ),
        aiTestSelfId,
        play,
        deck,
        hand,
      );

      final dragonOut = scoreWith([Card(CardFace.dragon, CardColor.special)]);
      final dragonGone = scoreWith([Card(CardFace.ten, CardColor.red)]);
      expect(dragonGone, greaterThan(dragonOut));
    });

    test('scores immediate hand-emptying play as 1000', () {
      final hand = [Card(CardFace.king, CardColor.red)];
      final play = TichuTurn(TurnType.single, hand);
      final score = scorer.scoreTurn(
        aiSnapshot(myHand: hand),
        aiTestSelfId,
        play,
        aiEmptyDeck(),
        hand,
      );

      expect(score, 1000);
    });

    test('prefers multi-card line over single when opponent at one', () {
      final hand = [
        Card(CardFace.three, CardColor.red),
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.six, CardColor.black),
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.king, CardColor.blue),
      ];
      final snapshot = aiSnapshot(
        myHand: hand,
        otherHands: {
          aiTestLeftId: [Card(CardFace.two, CardColor.red)],
          aiTestPartnerId: aiDefaultHand(),
          aiTestRightId: aiDefaultHand(),
        },
      );

      final straight = TichuTurn(TurnType.straight, [
        Card(CardFace.three, CardColor.red),
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.six, CardColor.black),
        Card(CardFace.seven, CardColor.red),
      ]);
      final single = TichuTurn(TurnType.single, [
        Card(CardFace.seven, CardColor.red),
      ]);

      final straightScore = scorer.scoreTurn(
        snapshot,
        aiTestSelfId,
        straight,
        aiEmptyDeck(),
        hand,
      );
      final singleScore = scorer.scoreTurn(
        snapshot,
        aiTestSelfId,
        single,
        aiEmptyDeck(),
        hand,
      );

      expect(straightScore, greaterThan(singleScore));
    });

    test('rewards disruption when opponent tichu near finish is winning', () {
      final hand = [
        Card(CardFace.six, CardColor.red),
        Card(CardFace.king, CardColor.blue),
      ];
      final deckTurn = TichuTurn(TurnType.single, [
        Card(CardFace.five, CardColor.black),
      ]);
      final deck = DeckState(deckTurn, CardFace.none)
        ..currentWinner = aiTestLeftId;
      final snapshot = aiSnapshot(
        myHand: hand,
        deck: deck,
        tichuCalls: {aiTestLeftId: TichuCall.tichu},
        otherHands: {
          aiTestLeftId: [
            Card(CardFace.ace, CardColor.red),
            Card(CardFace.queen, CardColor.green),
          ],
          aiTestPartnerId: aiDefaultHand(),
          aiTestRightId: aiDefaultHand(),
        },
        lastPlayedBy: aiTestLeftId,
        lastPlayedTurn: deckTurn,
      );

      final lowInterrupt = TichuTurn(TurnType.single, [
        Card(CardFace.six, CardColor.red),
      ]);
      final highInterrupt = TichuTurn(TurnType.single, [
        Card(CardFace.king, CardColor.blue),
      ]);

      final lowScore = scorer.scoreTurn(
        snapshot,
        aiTestSelfId,
        lowInterrupt,
        deck,
        hand,
      );
      final highScore = scorer.scoreTurn(
        snapshot,
        aiTestSelfId,
        highInterrupt,
        deck,
        hand,
      );

      expect(highScore, greaterThan(lowScore));
    });

    test('treats bomb as late when opponent called tichu', () {
      final hand = [
        Card(CardFace.five, CardColor.red),
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.king, CardColor.red),
      ];
      final bomb = TichuTurn(TurnType.bomb, [
        Card(CardFace.five, CardColor.red),
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.five, CardColor.black),
      ]);
      final noLowHands = {
        aiTestLeftId: aiDefaultHand(),
        aiTestPartnerId: aiDefaultHand(),
        aiTestRightId: aiDefaultHand(),
      };

      final earlySnapshot = aiSnapshot(myHand: hand, otherHands: noLowHands);
      final tichuSnapshot = aiSnapshot(
        myHand: hand,
        otherHands: noLowHands,
        tichuCalls: {aiTestLeftId: TichuCall.tichu},
      );

      final earlyScore = scorer.scoreTurn(
        earlySnapshot,
        aiTestSelfId,
        bomb,
        aiEmptyDeck(),
        hand,
      );
      final tichuLateScore = scorer.scoreTurn(
        tichuSnapshot,
        aiTestSelfId,
        bomb,
        aiEmptyDeck(),
        hand,
      );

      expect(tichuLateScore, greaterThan(earlyScore));
    });

    test('scores bomb higher when opponent is low', () {
      final hand = [
        Card(CardFace.five, CardColor.red),
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.king, CardColor.red),
      ];
      final bomb = TichuTurn(TurnType.bomb, [
        Card(CardFace.five, CardColor.red),
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.five, CardColor.black),
      ]);

      final lowOpponentSnapshot = aiSnapshot(
        myHand: hand,
        otherHands: {
          aiTestLeftId: [Card(CardFace.two, CardColor.red)],
          aiTestPartnerId: aiDefaultHand(),
          aiTestRightId: aiDefaultHand(),
        },
      );
      final normalSnapshot = aiSnapshot(
        myHand: hand,
        otherHands: {
          aiTestLeftId: aiDefaultHand(),
          aiTestPartnerId: aiDefaultHand(),
          aiTestRightId: aiDefaultHand(),
        },
      );

      final lateScore = scorer.scoreTurn(
        lowOpponentSnapshot,
        aiTestSelfId,
        bomb,
        aiEmptyDeck(),
        hand,
      );
      final earlyScore = scorer.scoreTurn(
        normalSnapshot,
        aiTestSelfId,
        bomb,
        aiEmptyDeck(),
        hand,
      );

      expect(lateScore, greaterThan(earlyScore));
    });
  });
}
