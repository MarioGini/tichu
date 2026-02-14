import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/schupf_strategy.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'ai_test_fixtures.dart';

void main() {
  const strategy = DefaultSchupfStrategy();

  group('DefaultSchupfStrategy', () {
    test('throws when fewer than 3 cards', () async {
      final snapshot = aiSnapshot(
        myHand: [
          Card(CardFace.two, CardColor.red),
          Card(CardFace.three, CardColor.blue),
        ],
      );

      expect(
        () => strategy.selectSchupfCards(snapshot, aiTestSelfId),
        throwsA(isA<StateError>()),
      );
    });

    test('avoids giving specials when normal cards exist', () async {
      final snapshot = aiSnapshot(
        myHand: [
          Card(CardFace.dragon, CardColor.special),
          Card(CardFace.phoenix, CardColor.special),
          Card(CardFace.dog, CardColor.special),
          Card(CardFace.mahJong, CardColor.special),
          Card(CardFace.two, CardColor.red),
          Card(CardFace.three, CardColor.blue),
          Card(CardFace.four, CardColor.green),
        ],
      );

      final action = await strategy.selectSchupfCards(snapshot, aiTestSelfId);
      final specialFaces = {
        CardFace.dragon,
        CardFace.phoenix,
        CardFace.dog,
        CardFace.mahJong,
      };

      expect(specialFaces.contains(action.toLeft.face), isFalse);
      expect(specialFaces.contains(action.toPartner.face), isFalse);
      expect(specialFaces.contains(action.toRight.face), isFalse);
    });

    test('gives best card to partner on partner grand tichu', () async {
      final snapshot = aiSnapshot(
        myHand: [
          Card(CardFace.two, CardColor.red),
          Card(CardFace.ten, CardColor.blue),
          Card(CardFace.ace, CardColor.green),
          Card(CardFace.king, CardColor.black),
        ],
        tichuCalls: {aiTestPartnerId: TichuCall.grandTichu},
      );

      final action = await strategy.selectSchupfCards(snapshot, aiTestSelfId);
      expect(action.toPartner.face, CardFace.ace);
    });

    test(
      'gives partner a low third card when self called grand tichu',
      () async {
        final snapshot = aiSnapshot(
          myHand: [
            Card(CardFace.two, CardColor.red),
            Card(CardFace.three, CardColor.blue),
            Card(CardFace.king, CardColor.green),
            Card(CardFace.ace, CardColor.black),
          ],
          tichuCalls: {aiTestSelfId: TichuCall.grandTichu},
        );

        final action = await strategy.selectSchupfCards(snapshot, aiTestSelfId);
        final opponentFaces = [action.toLeft.face, action.toRight.face]
          ..sort((a, b) => Card.getValue(a).compareTo(Card.getValue(b)));
        expect(opponentFaces, [CardFace.two, CardFace.three]);
        expect(action.toPartner.face, CardFace.king);
      },
    );

    test('keeps dog when partner called grand tichu', () async {
      final snapshot = aiSnapshot(
        myHand: [
          Card(CardFace.dog, CardColor.special),
          Card(CardFace.two, CardColor.red),
          Card(CardFace.three, CardColor.blue),
          Card(CardFace.ace, CardColor.green),
        ],
        tichuCalls: {aiTestPartnerId: TichuCall.grandTichu},
      );

      final action = await strategy.selectSchupfCards(snapshot, aiTestSelfId);
      expect(action.toLeft.face, isNot(CardFace.dog));
      expect(action.toPartner.face, CardFace.ace);
      expect(action.toRight.face, isNot(CardFace.dog));
    });

    test('gives dog to right opponent who called grand tichu', () async {
      final snapshot = aiSnapshot(
        myHand: [
          Card(CardFace.dog, CardColor.special),
          Card(CardFace.two, CardColor.red),
          Card(CardFace.three, CardColor.blue),
          Card(CardFace.four, CardColor.green),
        ],
        tichuCalls: {aiTestRightId: TichuCall.grandTichu},
      );

      final action = await strategy.selectSchupfCards(snapshot, aiTestSelfId);
      expect(action.toRight.face, CardFace.dog);
    });

    test('splits a low pair to opponents when available', () async {
      final snapshot = aiSnapshot(
        myHand: [
          Card(CardFace.three, CardColor.red),
          Card(CardFace.three, CardColor.blue),
          Card(CardFace.king, CardColor.green),
          Card(CardFace.ace, CardColor.black),
        ],
      );

      final action = await strategy.selectSchupfCards(snapshot, aiTestSelfId);
      expect(action.toLeft.face, CardFace.three);
      expect(action.toRight.face, CardFace.three);
    });

    test(
      'falls back to highest remaining card for partner when only specials remain',
      () async {
        final snapshot = aiSnapshot(
          myHand: [
            Card(CardFace.dragon, CardColor.special),
            Card(CardFace.phoenix, CardColor.special),
            Card(CardFace.dog, CardColor.special),
          ],
        );

        final action = await strategy.selectSchupfCards(snapshot, aiTestSelfId);
        expect(action.toPartner.face, CardFace.dragon);
      },
    );
  });
}
