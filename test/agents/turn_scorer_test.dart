import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/turn_scorer.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'ai_test_fixtures.dart';

void main() {
  const scorer = TurnScorer();

  group('TurnScorer', () {
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

    test('penalizes single leads when opponent has one card', () {
      final hand = [
        Card(CardFace.six, CardColor.red),
        Card(CardFace.king, CardColor.blue),
      ];
      final single = TichuTurn(TurnType.single, [
        Card(CardFace.six, CardColor.red),
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

      final lowOpponentScore = scorer.scoreTurn(
        lowOpponentSnapshot,
        aiTestSelfId,
        single,
        aiEmptyDeck(),
        hand,
      );
      final normalScore = scorer.scoreTurn(
        normalSnapshot,
        aiTestSelfId,
        single,
        aiEmptyDeck(),
        hand,
      );

      expect(lowOpponentScore, lessThan(normalScore));
    });

    test('adds trick-point capture reward when following', () {
      final hand = [
        Card(CardFace.king, CardColor.red),
        Card(CardFace.six, CardColor.blue),
      ];
      final deck = DeckState(
        TichuTurn(TurnType.single, [Card(CardFace.ten, CardColor.black)]),
        CardFace.none,
      );
      final play = TichuTurn(TurnType.single, [
        Card(CardFace.king, CardColor.red),
      ]);

      final withPoints = scorer.scoreTurn(
        aiSnapshot(myHand: hand, deck: deck),
        aiTestSelfId,
        play,
        deck,
        hand,
      );
      final noPointsDeck = DeckState(
        TichuTurn(TurnType.single, [Card(CardFace.nine, CardColor.black)]),
        CardFace.none,
      );
      final withoutPoints = scorer.scoreTurn(
        aiSnapshot(myHand: hand, deck: noPointsDeck),
        aiTestSelfId,
        play,
        noPointsDeck,
        hand,
      );

      expect(withPoints, greaterThan(withoutPoints));
    });

    test('rewards unbeatable line when an opponent is low', () {
      final hand = [
        Card(CardFace.three, CardColor.red),
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.six, CardColor.black),
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.king, CardColor.blue),
      ];
      final straight = TichuTurn(TurnType.straight, [
        Card(CardFace.three, CardColor.red),
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.six, CardColor.black),
        Card(CardFace.seven, CardColor.red),
      ]);
      final snapshot = aiSnapshot(
        myHand: hand,
        otherHands: {
          aiTestLeftId: [Card(CardFace.two, CardColor.red)],
          aiTestPartnerId: aiDefaultHand(),
          aiTestRightId: aiDefaultHand(),
        },
      );

      final unbeatableScore = scorer.scoreTurn(
        snapshot,
        aiTestSelfId,
        straight,
        aiEmptyDeck(),
        hand,
      );
      final single = TichuTurn(TurnType.single, [
        Card(CardFace.seven, CardColor.red),
      ]);
      final singleScore = scorer.scoreTurn(
        snapshot,
        aiTestSelfId,
        single,
        aiEmptyDeck(),
        hand,
      );

      expect(unbeatableScore, greaterThan(singleScore));
    });

    test('rewards strong leading line against near-finish tichu opponent', () {
      final hand = [
        Card(CardFace.four, CardColor.red),
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.king, CardColor.green),
      ];
      final pairLead = TichuTurn(TurnType.pair, [
        Card(CardFace.four, CardColor.red),
        Card(CardFace.four, CardColor.blue),
      ]);
      final softSingle = TichuTurn(TurnType.single, [
        Card(CardFace.king, CardColor.green),
      ]);
      final snapshot = aiSnapshot(
        myHand: hand,
        tichuCalls: {aiTestLeftId: TichuCall.tichu},
        otherHands: {
          aiTestLeftId: [
            Card(CardFace.ace, CardColor.red),
            Card(CardFace.queen, CardColor.green),
          ],
          aiTestPartnerId: aiDefaultHand(),
          aiTestRightId: aiDefaultHand(),
        },
      );

      final pairScore = scorer.scoreTurn(
        snapshot,
        aiTestSelfId,
        pairLead,
        aiEmptyDeck(),
        hand,
      );
      final singleScore = scorer.scoreTurn(
        snapshot,
        aiTestSelfId,
        softSingle,
        aiEmptyDeck(),
        hand,
      );

      expect(pairScore, greaterThan(singleScore));
    });

    test('adds partner-lead bonus when playing dog', () {
      final hand = [
        Card(CardFace.dog, CardColor.special),
        Card(CardFace.king, CardColor.red),
      ];
      final dog = TichuTurn(TurnType.dog, [
        Card(CardFace.dog, CardColor.special),
      ]);
      final single = TichuTurn(TurnType.single, [
        Card(CardFace.king, CardColor.red),
      ]);

      final dogScore = scorer.scoreTurn(
        aiSnapshot(myHand: hand),
        aiTestSelfId,
        dog,
        aiEmptyDeck(),
        hand,
      );
      final singleScore = scorer.scoreTurn(
        aiSnapshot(myHand: hand),
        aiTestSelfId,
        single,
        aiEmptyDeck(),
        hand,
      );

      expect(dogScore, greaterThan(singleScore));
    });

    test('penalizes overtaking a partner tichu-winning trick', () {
      final hand = [
        Card(CardFace.king, CardColor.red),
        Card(CardFace.ace, CardColor.blue),
      ];
      final deck = DeckState(
        TichuTurn(TurnType.single, [Card(CardFace.queen, CardColor.black)]),
        CardFace.none,
      )..currentWinner = aiTestPartnerId;
      final snapshot = aiSnapshot(
        myHand: hand,
        deck: deck,
        tichuCalls: {aiTestPartnerId: TichuCall.tichu},
        lastPlayedBy: aiTestPartnerId,
      );

      final lowPlay = TichuTurn(TurnType.single, [
        Card(CardFace.king, CardColor.red),
      ]);
      final highPlay = TichuTurn(TurnType.single, [
        Card(CardFace.ace, CardColor.blue),
      ]);

      final lowScore = scorer.scoreTurn(
        snapshot,
        aiTestSelfId,
        lowPlay,
        deck,
        hand,
      );
      final highScore = scorer.scoreTurn(
        snapshot,
        aiTestSelfId,
        highPlay,
        deck,
        hand,
      );

      expect(highScore, lessThan(lowScore));
    });

    test('handles phoenix card removal when scoring', () {
      final hand = [
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.king, CardColor.red),
      ];
      final play = TichuTurn(TurnType.single, [
        Card(CardFace.phoenix, CardColor.special),
      ]);

      final score = scorer.scoreTurn(
        aiSnapshot(myHand: hand),
        aiTestSelfId,
        play,
        aiEmptyDeck(),
        hand,
      );

      expect(score.isFinite, isTrue);
    });
  });
}
