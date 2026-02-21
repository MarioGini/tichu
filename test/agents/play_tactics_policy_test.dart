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

    test(
      'selectPartnerSupportPass returns null when partner called but opponent is leading',
      () {
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
      },
    );

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

    test(
      'selectPartnerSupportPass does not auto-pass when self also called tichu',
      () {
        final deckTurn = TichuTurn(TurnType.single, [
          Card(CardFace.five, CardColor.red),
        ]);
        final deck = DeckState(deckTurn, CardFace.none)
          ..currentWinner = aiTestLeftId;
        final snapshot = aiSnapshot(
          myHand: [Card(CardFace.six, CardColor.blue)],
          deck: deck,
          tichuCalls: {
            aiTestSelfId: TichuCall.tichu,
            aiTestPartnerId: TichuCall.grandTichu,
          },
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
      },
    );

    test(
      'selectPartnerSupportPass returns null when partner call owner is already finished',
      () {
        final deckTurn = TichuTurn(TurnType.single, [
          Card(CardFace.five, CardColor.red),
        ]);
        final deck = DeckState(deckTurn, CardFace.none)
          ..currentWinner = aiTestLeftId;
        final snapshot = aiSnapshot(
          myHand: [Card(CardFace.six, CardColor.blue)],
          deck: deck,
          tichuCalls: {aiTestPartnerId: TichuCall.tichu},
          otherHands: {
            aiTestLeftId: aiDefaultHand(),
            aiTestPartnerId: const <Card>[],
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
      },
    );

    test(
      'selectPartnerGrandTichuDogLead returns dog when leading after own win',
      () {
        final snapshot = aiSnapshot(
          myHand: [
            Card(CardFace.dog, CardColor.special),
            Card(CardFace.five, CardColor.red),
          ],
          tichuCalls: {aiTestPartnerId: TichuCall.grandTichu},
          lastPlayedBy: aiTestSelfId,
        );
        final legalTurns = [
          TichuTurn(TurnType.dog, [Card(CardFace.dog, CardColor.special)]),
          TichuTurn(TurnType.single, [Card(CardFace.five, CardColor.red)]),
        ];

        final selected = policy.selectPartnerGrandTichuDogLead(
          playerId: aiTestSelfId,
          snapshot: snapshot,
          legalTurns: legalTurns,
          isLeading: true,
          table: TableRelationships(snapshot, aiTestSelfId),
        );

        expect(selected, isNotNull);
        expect(selected!.type, TurnType.dog);
      },
    );

    test('selectEarlyDogLead returns dog when leading', () {
      final legalTurns = [
        TichuTurn(TurnType.dog, [Card(CardFace.dog, CardColor.special)]),
        TichuTurn(TurnType.single, [Card(CardFace.five, CardColor.red)]),
      ];

      final selected = policy.selectEarlyDogLead(
        legalTurns: legalTurns,
        isLeading: true,
      );

      expect(selected, isNotNull);
      expect(selected!.type, TurnType.dog);
    });

    test('selectSingletonResponse prefers lowest true singleton', () {
      final hand = [
        Card(CardFace.five, CardColor.red),
        Card(CardFace.eight, CardColor.red),
        Card(CardFace.eight, CardColor.blue),
        Card(CardFace.king, CardColor.green),
      ];
      final deck = DeckState(
        TichuTurn(TurnType.single, [Card(CardFace.three, CardColor.black)]),
        CardFace.none,
      );
      final legalTurns = [
        TichuTurn(TurnType.single, [Card(CardFace.five, CardColor.red)]),
        TichuTurn(TurnType.single, [Card(CardFace.eight, CardColor.red)]),
        TichuTurn(TurnType.single, [Card(CardFace.eight, CardColor.blue)]),
        TichuTurn(TurnType.single, [Card(CardFace.king, CardColor.green)]),
      ];

      final selected = policy.selectSingletonResponse(
        legalTurns: legalTurns,
        deck: deck,
        hand: hand,
      );

      expect(selected, isNotNull);
      expect(selected!.cards.first.face, CardFace.five);
    });

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
