import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'smart_ai_test_helpers.dart';

void main() {
  late SmartAiAgent agent;

  setUp(() {
    agent = SmartAiAgent(aiId);
  });

  group('wish selection', () {
    test('prefers the card schupfed to the next player', () async {
      final forcedWish = Card(CardFace.seven, CardColor.red);
      final schupfAgent = SmartAiAgent(
        aiId,
        schupfStrategy: FixedSchupfStrategy(
          toLeft: forcedWish,
          toPartner: Card(CardFace.three, CardColor.green),
          toRight: Card(CardFace.two, CardColor.black),
        ),
      );

      final schupfSnapshot = aiSnapshot(
        myHand: [
          forcedWish,
          Card(CardFace.mahJong, CardColor.special),
          Card(CardFace.ace, CardColor.blue),
          Card(CardFace.king, CardColor.green),
        ],
      );
      await schupfAgent.selectSchupfCards(schupfSnapshot);

      final playSnapshot = aiSnapshot(
        myHand: [
          Card(CardFace.mahJong, CardColor.special),
          Card(CardFace.seven, CardColor.blue),
          Card(CardFace.ace, CardColor.blue),
        ],
        deck: emptyDeck(),
      );

      final action = await schupfAgent.selectTurn(playSnapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      if (play.cards.any((c) => c.face == CardFace.mahJong)) {
        expect(play.inputWish, CardFace.seven);
      }
    });

    test('wishes for a high card not in hand', () async {
      final hand = [
        Card(CardFace.mahJong, CardColor.special),
        Card(CardFace.two, CardColor.red),
        Card(CardFace.five, CardColor.blue),
      ];
      final snapshot = aiSnapshot(myHand: hand, deck: emptyDeck());

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      // The agent should wish for a high card it doesn't hold.
      if (play.cards.any((c) => c.face == CardFace.mahJong)) {
        expect(
          play.inputWish,
          isIn([
            CardFace.ace,
            CardFace.king,
            CardFace.queen,
            CardFace.jack,
            CardFace.ten,
          ]),
        );
      }
    });

    test('returns no wish when holding all high cards', () async {
      final hand = [
        Card(CardFace.mahJong, CardColor.special),
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.king, CardColor.blue),
        Card(CardFace.queen, CardColor.green),
        Card(CardFace.jack, CardColor.black),
        Card(CardFace.ten, CardColor.red),
      ];
      final snapshot = aiSnapshot(myHand: hand, deck: emptyDeck());

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      if (play.cards.any((c) => c.face == CardFace.mahJong)) {
        expect(play.inputWish, CardFace.none);
      }
    });
  });

  group('selectDragonGive', () {
    test('avoids opponent who declared tichu', () async {
      final agent = SmartAiAgent(aiId);

      final snapshot = aiSnapshot(
        myHand: [Card(CardFace.dragon, CardColor.special)],
        otherHands: {
          leftId: List.generate(6, (i) => Card(CardFace.two, CardColor.red)),
          partnerId: defaultHand(),
          rightId: List.generate(2, (i) => Card(CardFace.two, CardColor.blue)),
        },
        tichuCalls: {leftId: TichuCall.tichu},
      );

      final seat = await agent.selectDragonGive(snapshot);
      // Left declared Tichu → give to right opponent.
      expect(seat, 3);
    });

    test('gives to opponent with more cards', () async {
      final agent = SmartAiAgent(aiId);

      // Left has 8 cards, right has 3 cards.
      final snapshot = aiSnapshot(
        myHand: [Card(CardFace.dragon, CardColor.special)],
        otherHands: {
          leftId: List.generate(8, (i) => Card(CardFace.two, CardColor.red)),
          partnerId: defaultHand(),
          rightId: List.generate(3, (i) => Card(CardFace.two, CardColor.blue)),
        },
      );

      final seat = await agent.selectDragonGive(snapshot);
      // Left opponent (seat 1) has more cards → should give to seat 1.
      expect(seat, 1);
    });

    test('gives to right opponent when right has more cards', () async {
      final agent = SmartAiAgent(aiId);

      final snapshot = aiSnapshot(
        myHand: [Card(CardFace.dragon, CardColor.special)],
        otherHands: {
          leftId: List.generate(2, (i) => Card(CardFace.two, CardColor.red)),
          partnerId: defaultHand(),
          rightId: List.generate(10, (i) => Card(CardFace.two, CardColor.blue)),
        },
      );

      final seat = await agent.selectDragonGive(snapshot);
      // Right opponent (seat 3) has more cards → should give to seat 3.
      expect(seat, 3);
    });
  });
}
