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

  group('selectTurn', () {
    test('passes when hand is empty', () async {
      final snapshot = aiSnapshot(myHand: []);
      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PassAction>());
    });

    test('plays a legal single card on empty deck', () async {
      final hand = [
        Card(CardFace.five, CardColor.red),
        Card(CardFace.ten, CardColor.blue),
      ];
      final snapshot = aiSnapshot(myHand: hand, deck: emptyDeck());
      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      // Must be a card from the hand.
      for (final c in play.cards) {
        expect(
          hand.any((final h) => h.face == c.face),
          true,
          reason: 'played card ${c.face} should be from hand',
        );
      }
    });

    test('returns play cards as mutable list', () async {
      final snapshot = aiSnapshot(
        myHand: [Card(CardFace.phoenix, CardColor.special)],
        deck: emptyDeck(),
      );

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());

      final play = action as PlayTurnAction;
      expect(play.cards.single.face, CardFace.phoenix);
      expect(() => play.cards.sort(compareCards), returnsNormally);
    });

    test('follows with a higher single when required', () async {
      final hand = [
        Card(CardFace.three, CardColor.red),
        Card(CardFace.eight, CardColor.blue),
        Card(CardFace.king, CardColor.green),
      ];
      final deckTurn = TichuTurn(TurnType.single, [
        Card(CardFace.five, CardColor.black),
      ]);
      final deck = DeckState(deckTurn, CardFace.none);
      deck.currentWinner = leftId;
      final snapshot = aiSnapshot(myHand: hand, deck: deck);

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      expect(play.cards.length, 1);
      // The played card must beat the 5 on the deck.
      expect(play.cards.first.value, greaterThan(5));
    });

    test('passes when it cannot beat the deck', () async {
      final hand = [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.three, CardColor.blue),
      ];
      final deckTurn = TichuTurn(TurnType.single, [
        Card(CardFace.ace, CardColor.black),
      ]);
      final deck = DeckState(deckTurn, CardFace.none);
      deck.currentWinner = leftId;
      final snapshot = aiSnapshot(myHand: hand, deck: deck);

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PassAction>());
    });

    test('does not play phoenix as single on low card', () async {
      final hand = [
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.seven, CardColor.red),
      ];
      final deckTurn = TichuTurn(TurnType.single, [
        Card(CardFace.six, CardColor.black),
      ]);
      final deck = DeckState(deckTurn, CardFace.none);
      deck.currentWinner = leftId;
      final snapshot = aiSnapshot(myHand: hand, deck: deck);

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      expect(play.cards.length, 1);
      expect(play.cards.first.face, CardFace.seven);
    });

    test('prefers ace over phoenix when ace already wins the trick', () async {
      final hand = [
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.ace, CardColor.red),
      ];
      final deckTurn = TichuTurn(TurnType.single, [
        Card(CardFace.king, CardColor.black),
      ]);
      final deck = DeckState(deckTurn, CardFace.none);
      deck.currentWinner = leftId;
      final snapshot = aiSnapshot(myHand: hand, deck: deck);

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      expect(play.cards.length, 1);
      expect(play.cards.first.face, CardFace.ace);
    });

    test(
      'plays when tactics policy filters all valid plays but pass is illegal',
      () async {
        final customAgent = SmartAiAgent(
          aiId,
          playTacticsPolicy: const ForceEmptyValidPlaysPolicy(),
        );
        final hand = [
          Card(CardFace.five, CardColor.red),
          Card(CardFace.king, CardColor.blue),
        ];

        final action = await customAgent.selectTurn(
          aiSnapshot(myHand: hand, deck: emptyDeck()),
        );

        expect(action, isA<PlayTurnAction>());
      },
    );

    test('prefers non-bomb plays', () async {
      final hand = [
        Card(CardFace.five, CardColor.red),
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.ten, CardColor.red),
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
      // Should play the ten as a single instead of bombing with four 5s.
      expect(play.cards.length, 1);
    });

    test('plays all remaining cards to go out', () async {
      // Only one card left → must play it.
      final hand = [Card(CardFace.king, CardColor.red)];
      final snapshot = aiSnapshot(myHand: hand, deck: emptyDeck());
      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      expect(play.cards.length, 1);
      expect(play.cards.first.face, CardFace.king);
    });

    test('plays phoenix pair to finish when legal', () async {
      final hand = [
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.king, CardColor.red),
      ];
      final snapshot = aiSnapshot(myHand: hand, deck: emptyDeck());

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      expect(play.cards.length, 2);
      expect(getTurn(play.cards).type, TurnType.pair);
    });

    test('does not go out ahead of a partner who called Tichu', () async {
      final hand = [
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.king, CardColor.red),
      ];
      final deckTurn = TichuTurn(TurnType.pair, [
        Card(CardFace.queen, CardColor.black),
        Card(CardFace.queen, CardColor.red),
      ]);
      final deck = DeckState(deckTurn, CardFace.none);
      deck.currentWinner = partnerId;

      final snapshot = aiSnapshot(
        myHand: hand,
        deck: deck,
        tichuCalls: {partnerId: TichuCall.tichu},
        lastPlayedBy: partnerId,
        lastPlayedTurn: deckTurn,
      );

      final action = await agent.selectTurn(snapshot);
      // Going out first would make the partner's Tichu fail (-100).
      expect(action, isA<PassAction>());
    });
  });
}
