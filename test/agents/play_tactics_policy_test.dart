import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/play_tactics_policy.dart';
import 'package:tichu/agents/table_relationships.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'ai_test_fixtures.dart';

void main() {
  const policy = PlayTacticsPolicy();

  group('PlayTacticsPolicy', () {
    test('selectPartnerFinishLead chooses lowest non-dragon single', () {
      final snapshot = aiSnapshot(
        myHand: aiDefaultHand(),
        tichuCalls: {aiTestPartnerId: TichuCall.tichu},
        otherHands: {
          aiTestLeftId: aiDefaultHand(),
          aiTestPartnerId: [Card(CardFace.ace, CardColor.red)],
          aiTestRightId: aiDefaultHand(),
        },
      );
      final legalTurns = [
        TichuTurn(TurnType.single, [Card(CardFace.dragon, CardColor.special)]),
        TichuTurn(TurnType.single, [Card(CardFace.five, CardColor.red)]),
      ];

      final selected = policy.selectPartnerFinishLead(
        snapshot: snapshot,
        legalTurns: legalTurns,
        isLeading: true,
        table: TableRelationships(snapshot, aiTestSelfId),
      );

      expect(selected, isNotNull);
      expect(selected!.cards.first.face, CardFace.five);
    });

    test(
      'selectPartnerSupportPass returns pass on partner high winning trick',
      () {
        final deckTurn = TichuTurn(TurnType.single, [
          Card(CardFace.king, CardColor.red),
        ]);
        final deck = DeckState(deckTurn, CardFace.none)
          ..currentWinner = aiTestPartnerId;
        final snapshot = aiSnapshot(
          myHand: [
            Card(CardFace.ace, CardColor.red),
            Card(CardFace.ten, CardColor.blue),
          ],
          deck: deck,
          tichuCalls: {aiTestPartnerId: TichuCall.tichu},
          lastPlayedBy: aiTestPartnerId,
          lastPlayedTurn: deckTurn,
        );

        final pass = policy.selectPartnerSupportPass(
          playerId: aiTestSelfId,
          snapshot: snapshot,
          deck: deck,
          hand: snapshot.hands[aiTestSelfId]!,
          table: TableRelationships(snapshot, aiTestSelfId),
        );

        expect(pass, isA<PassAction>());
      },
    );

    test('selectPartnerSupportPass returns pass on partner winning combo', () {
      final deckTurn = TichuTurn(TurnType.pair, [
        Card(CardFace.ten, CardColor.red),
        Card(CardFace.ten, CardColor.blue),
      ]);
      final deck = DeckState(deckTurn, CardFace.none)
        ..currentWinner = aiTestPartnerId;
      final snapshot = aiSnapshot(
        myHand: [
          Card(CardFace.ace, CardColor.red),
          Card(CardFace.jack, CardColor.green),
        ],
        deck: deck,
        tichuCalls: {aiTestPartnerId: TichuCall.tichu},
        lastPlayedBy: aiTestPartnerId,
        lastPlayedTurn: deckTurn,
      );

      final pass = policy.selectPartnerSupportPass(
        playerId: aiTestSelfId,
        snapshot: snapshot,
        deck: deck,
        hand: snapshot.hands[aiTestSelfId]!,
        table: TableRelationships(snapshot, aiTestSelfId),
      );

      expect(pass, isA<PassAction>());
    });

    test('selectPartnerSupportPass returns null when partner called but opponent is leading', () {
      final deckTurn = TichuTurn(TurnType.single, [
        Card(CardFace.five, CardColor.red),
      ]);
      final deck = DeckState(deckTurn, CardFace.none)
        ..currentWinner = aiTestLeftId;
      final snapshot = aiSnapshot(
        myHand: [Card(CardFace.six, CardColor.blue)],
        deck: deck,
        tichuCalls: {aiTestPartnerId: TichuCall.grandTichu},
        otherHands: {
          aiTestLeftId: aiDefaultHand(),
          aiTestPartnerId: [Card(CardFace.ace, CardColor.red)],
          aiTestRightId: aiDefaultHand(),
        },
        lastPlayedBy: aiTestLeftId,
        lastPlayedTurn: deckTurn,
      );

      final pass = policy.selectPartnerSupportPass(
        playerId: aiTestSelfId,
        snapshot: snapshot,
        deck: deck,
        hand: snapshot.hands[aiTestSelfId]!,
        table: TableRelationships(snapshot, aiTestSelfId),
      );

      expect(pass, isNull);
    });

    test('selectPartnerSupportPass returns null when wish is fulfillable', () {
      final deckTurn = TichuTurn(TurnType.single, [
        Card(CardFace.five, CardColor.red),
      ]);
      final deck = DeckState(deckTurn, CardFace.seven)
        ..currentWinner = aiTestLeftId;
      final snapshot = aiSnapshot(
        myHand: [
          Card(CardFace.seven, CardColor.blue),
          Card(CardFace.jack, CardColor.green),
        ],
        deck: deck,
        tichuCalls: {aiTestPartnerId: TichuCall.grandTichu},
        otherHands: {
          aiTestLeftId: aiDefaultHand(),
          aiTestPartnerId: [Card(CardFace.ace, CardColor.red)],
          aiTestRightId: aiDefaultHand(),
        },
        lastPlayedBy: aiTestLeftId,
        lastPlayedTurn: deckTurn,
      );

      final pass = policy.selectPartnerSupportPass(
        playerId: aiTestSelfId,
        snapshot: snapshot,
        deck: deck,
        hand: snapshot.hands[aiTestSelfId]!,
        table: TableRelationships(snapshot, aiTestSelfId),
      );

      expect(pass, isNull);
    });
  });
}
