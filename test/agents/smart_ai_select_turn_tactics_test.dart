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
    test('avoids burning high cards early when leading', () async {
      final hand = [
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.king, CardColor.blue),
        Card(CardFace.queen, CardColor.green),
        Card(CardFace.jack, CardColor.black),
        Card(CardFace.three, CardColor.red),
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.six, CardColor.black),
        Card(CardFace.seven, CardColor.red),
      ];
      final snapshot = aiSnapshot(myHand: hand, deck: emptyDeck());

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;

      final playedFaces = play.cards.map((c) => c.face).toSet();
      expect(playedFaces.contains(CardFace.ace), false);
      expect(playedFaces.contains(CardFace.king), false);
    });

    test('prefers multi-card lines when opponent is low', () async {
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
        deck: emptyDeck(),
        otherHands: {
          leftId: List.generate(4, (i) => Card(CardFace.two, CardColor.red)),
          partnerId: defaultHand(),
          rightId: [
            ...List.generate(5, (i) => Card(CardFace.three, CardColor.blue)),
            // An unseen Ace, so the King is not a sure winner.
            Card(CardFace.ace, CardColor.green),
          ],
        },
      );

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      expect(getTurn(play.cards).type, TurnType.straight);
    });

    test('avoids singles when opponent has 1 card', () async {
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
        deck: emptyDeck(),
        otherHands: {
          leftId: [Card(CardFace.two, CardColor.red)],
          partnerId: defaultHand(),
          rightId: [
            ...List.generate(5, (i) => Card(CardFace.three, CardColor.blue)),
            // An unseen Ace, so the King is not a sure winner.
            Card(CardFace.ace, CardColor.green),
          ],
        },
      );

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      expect(getTurn(play.cards).type, TurnType.straight);
    });

    test('passes to support partner tichu when partner is winning', () async {
      final hand = [
        Card(CardFace.nine, CardColor.red),
        Card(CardFace.jack, CardColor.blue),
      ];
      final deckTurn = TichuTurn(TurnType.single, [
        Card(CardFace.king, CardColor.black),
      ]);
      final deck = DeckState(deckTurn, CardFace.none);

      final snapshot = aiSnapshot(
        myHand: hand,
        deck: deck,
        otherHands: {
          leftId: defaultHand(),
          partnerId: [
            Card(CardFace.two, CardColor.red),
            Card(CardFace.three, CardColor.blue),
            Card(CardFace.four, CardColor.green),
            Card(CardFace.five, CardColor.red),
          ],
          rightId: defaultHand(),
        },
        tichuCalls: {partnerId: TichuCall.tichu},
        lastPlayedBy: partnerId,
        lastPlayedTurn: deckTurn,
      );

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PassAction>());
    });

    test('never goes out ahead of a partner who called Tichu', () async {
      final hand = [Card(CardFace.six, CardColor.red)];
      final deckTurn = TichuTurn(TurnType.single, [
        Card(CardFace.five, CardColor.black),
      ]);
      final deck = DeckState(deckTurn, CardFace.none);
      final snapshot = aiSnapshot(
        myHand: hand,
        deck: deck,
        otherHands: {
          leftId: [
            Card(CardFace.two, CardColor.red),
            Card(CardFace.nine, CardColor.blue),
          ],
          partnerId: [Card(CardFace.ace, CardColor.red)],
          rightId: defaultHand(),
        },
        tichuCalls: {partnerId: TichuCall.tichu},
        lastPlayedBy: leftId,
        lastPlayedTurn: deckTurn,
      );

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PassAction>());
    });

    test('holds back its last card while partner Tichu is open and opponents '
        'are not close', () async {
      final hand = [Card(CardFace.six, CardColor.red)];
      final deckTurn = TichuTurn(TurnType.single, [
        Card(CardFace.five, CardColor.black),
      ]);
      final deck = DeckState(deckTurn, CardFace.none);
      deck.currentWinner = leftId;

      final snapshot = aiSnapshot(
        myHand: hand,
        deck: deck,
        otherHands: {
          leftId: defaultHand(),
          partnerId: [Card(CardFace.ace, CardColor.red)],
          rightId: defaultHand(),
        },
        tichuCalls: {partnerId: TichuCall.tichu},
        lastPlayedBy: leftId,
        lastPlayedTurn: deckTurn,
      );

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PassAction>());
    });

    test(
      'passes when partner is winning a high trick without tichu call',
      () async {
        final hand = [
          Card(CardFace.ace, CardColor.red),
          Card(CardFace.ten, CardColor.blue),
        ];
        final deckTurn = TichuTurn(TurnType.single, [
          Card(CardFace.king, CardColor.black),
        ]);
        final deck = DeckState(deckTurn, CardFace.none);
        deck.currentWinner = partnerId;

        final snapshot = aiSnapshot(
          myHand: hand,
          deck: deck,
          otherHands: {
            leftId: defaultHand(),
            partnerId: [
              Card(CardFace.three, CardColor.red),
              Card(CardFace.four, CardColor.blue),
              Card(CardFace.five, CardColor.green),
            ],
            rightId: defaultHand(),
          },
          lastPlayedBy: partnerId,
          lastPlayedTurn: deckTurn,
        );

        final action = await agent.selectTurn(snapshot);
        expect(action, isA<PassAction>());
      },
    );
  });
}
