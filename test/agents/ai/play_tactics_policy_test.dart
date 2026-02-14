import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/agents/ai/play_tactics_policy.dart';
import 'package:tichu/agents/ai/table_relationships.dart';
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

    test('filterWishValidPlays enforces mahjong wish constraint', () {
      final deck = DeckState(
        TichuTurn(TurnType.single, [Card(CardFace.five, CardColor.red)]),
        CardFace.seven,
      );
      final hand = [
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.king, CardColor.blue),
      ];
      final legalTurns = [
        TichuTurn(TurnType.single, [Card(CardFace.seven, CardColor.red)]),
        TichuTurn(TurnType.single, [Card(CardFace.king, CardColor.blue)]),
      ];

      final valid = policy.filterWishValidPlays(
        deck: deck,
        legalTurns: legalTurns,
        hand: hand,
      );

      expect(valid, hasLength(1));
      expect(valid.first.cards.first.face, CardFace.seven);
    });
  });
}
