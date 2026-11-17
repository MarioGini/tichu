import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/find_turn.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'smart_ai_test_helpers.dart';

void main() {
  late SmartAiAgent agent;

  setUp(() {
    agent = SmartAiAgent(aiId);
  });

  group('selectTurn tactics', () {
    test('may take over a low single from the partner', () async {
      final hand = [
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.nine, CardColor.blue),
      ];
      final deckTurn = TichuTurn(TurnType.single, [
        Card(CardFace.four, CardColor.black),
      ]);
      final deck = DeckState(deckTurn, CardFace.none);
      final snapshot = aiSnapshot(
        myHand: hand,
        deck: deck,
        otherHands: {
          leftId: defaultHand(),
          partnerId: [
            Card(CardFace.three, CardColor.red),
            Card(CardFace.five, CardColor.green),
          ],
          rightId: defaultHand(),
        },
        lastPlayedBy: partnerId,
        lastPlayedTurn: deckTurn,
      );

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
    });

    test('leads a single to help partner finish tichu', () async {
      final hand = [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.ten, CardColor.blue),
      ];

      final snapshot = aiSnapshot(
        myHand: hand,
        deck: emptyDeck(),
        otherHands: {
          leftId: defaultHand(),
          partnerId: [Card(CardFace.ace, CardColor.red)],
          rightId: defaultHand(),
        },
        tichuCalls: {partnerId: TichuCall.tichu},
      );

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      expect(getTurn(play.cards).type, TurnType.single);
      expect(play.cards.first.face, CardFace.two);
    });

    test('plays dog early when leading', () async {
      final hand = [
        Card(CardFace.dog, CardColor.special),
        Card(CardFace.five, CardColor.blue),
      ];

      final snapshot = aiSnapshot(myHand: hand, deck: emptyDeck());

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      expect(getTurn(play.cards).type, TurnType.dog);
    });

    test(
      'leads mahjong instead of dog on game opening when both are in hand',
      () async {
        final hand = [
          Card(CardFace.dog, CardColor.special),
          Card(CardFace.mahJong, CardColor.special),
          Card(CardFace.king, CardColor.blue),
        ];

        final snapshot = aiSnapshot(myHand: hand, deck: emptyDeck());

        final action = await agent.selectTurn(snapshot);
        expect(action, isA<PlayTurnAction>());
        final play = action as PlayTurnAction;
        expect(play.cards.any((final c) => c.face == CardFace.mahJong), isTrue);
        expect(getTurn(play.cards).type, isNot(TurnType.dog));
      },
    );

    test(
      'prefers mahjong straight lead over dog on game opening when available',
      () async {
        final hand = [
          Card(CardFace.dog, CardColor.special),
          Card(CardFace.mahJong, CardColor.special),
          Card(CardFace.two, CardColor.red),
          Card(CardFace.three, CardColor.blue),
          Card(CardFace.four, CardColor.green),
          Card(CardFace.five, CardColor.black),
        ];

        final snapshot = aiSnapshot(myHand: hand, deck: emptyDeck());

        final action = await agent.selectTurn(snapshot);
        expect(action, isA<PlayTurnAction>());
        final play = action as PlayTurnAction;
        expect(play.cards.any((final c) => c.face == CardFace.mahJong), isTrue);
        expect(getTurn(play.cards).type, TurnType.straight);
      },
    );

    test('skips mahjong opening rule after first card of game', () async {
      final hand = [
        Card(CardFace.dog, CardColor.special),
        Card(CardFace.mahJong, CardColor.special),
        Card(CardFace.king, CardColor.blue),
      ];
      final priorTurn = TichuTurn(TurnType.single, [
        Card(CardFace.five, CardColor.black),
      ]);

      final snapshot = aiSnapshot(
        myHand: hand,
        deck: emptyDeck(),
        lastPlayedBy: leftId,
        lastPlayedTurn: priorTurn,
      );

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      expect(getTurn(play.cards).type, TurnType.dog);
    });

    test(
      'responds to single with lowest singleton and preserves pair',
      () async {
        final hand = [
          Card(CardFace.five, CardColor.red),
          Card(CardFace.eight, CardColor.red),
          Card(CardFace.eight, CardColor.blue),
          Card(CardFace.king, CardColor.green),
        ];
        final deckTurn = TichuTurn(TurnType.single, [
          Card(CardFace.three, CardColor.black),
        ]);
        final deck = DeckState(deckTurn, CardFace.none);
        deck.currentWinner = leftId;
        final snapshot = aiSnapshot(myHand: hand, deck: deck);

        final action = await agent.selectTurn(snapshot);
        expect(action, isA<PlayTurnAction>());
        final play = action as PlayTurnAction;
        expect(getTurn(play.cards).type, TurnType.single);
        expect(play.cards.first.face, CardFace.five);
      },
    );
  });
}
