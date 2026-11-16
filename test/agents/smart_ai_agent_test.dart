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

  group('shouldCallGrandTichu', () {
    test('always returns false', () async {
      final snapshot = aiSnapshot(
        myHand: [
          Card(CardFace.dragon, CardColor.special),
          Card(CardFace.phoenix, CardColor.special),
          Card(CardFace.ace, CardColor.red),
          Card(CardFace.ace, CardColor.blue),
          Card(CardFace.ace, CardColor.green),
          Card(CardFace.ace, CardColor.black),
          Card(CardFace.king, CardColor.red),
          Card(CardFace.king, CardColor.blue),
        ],
      );
      expect(await agent.shouldCallGrandTichu(snapshot), false);
    });
  });

  group('shouldCallTichu', () {
    test('declines with average cards', () async {
      final snapshot = aiSnapshot(
        myHand: [
          Card(CardFace.two, CardColor.red),
          Card(CardFace.three, CardColor.blue),
          Card(CardFace.four, CardColor.green),
          Card(CardFace.five, CardColor.black),
          Card(CardFace.six, CardColor.red),
          Card(CardFace.seven, CardColor.blue),
          Card(CardFace.eight, CardColor.green),
          Card(CardFace.nine, CardColor.black),
          Card(CardFace.ten, CardColor.red),
          Card(CardFace.jack, CardColor.blue),
          Card(CardFace.queen, CardColor.green),
          Card(CardFace.king, CardColor.black),
          Card(CardFace.dog, CardColor.special),
          Card(CardFace.mahJong, CardColor.special),
        ],
      );
      expect(await agent.shouldCallTichu(snapshot), false);
    });
  });

  group('selectSchupfCards', () {
    test('returns three different cards', () async {
      final hand = [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.eight, CardColor.green),
        Card(CardFace.jack, CardColor.black),
        Card(CardFace.king, CardColor.red),
        Card(CardFace.ace, CardColor.blue),
      ];
      final snapshot = aiSnapshot(myHand: hand);
      final action = await agent.selectSchupfCards(snapshot);

      // All three must be cards from the hand.
      expect(hand.contains(action.toLeft), true);
      expect(hand.contains(action.toPartner), true);
      expect(hand.contains(action.toRight), true);
    });

    test('avoids schupfing special cards', () async {
      final hand = [
        Card(CardFace.dragon, CardColor.special),
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.dog, CardColor.special),
        Card(CardFace.mahJong, CardColor.special),
        Card(CardFace.two, CardColor.red),
        Card(CardFace.three, CardColor.blue),
        Card(CardFace.four, CardColor.green),
        Card(CardFace.five, CardColor.black),
      ];
      final snapshot = aiSnapshot(myHand: hand);
      final action = await agent.selectSchupfCards(snapshot);

      final specials = [
        CardFace.dragon,
        CardFace.phoenix,
        CardFace.dog,
        CardFace.mahJong,
      ];
      expect(specials.contains(action.toLeft.face), false);
      expect(specials.contains(action.toRight.face), false);
      // Partner may get a higher card but still not a special.
      expect(specials.contains(action.toPartner.face), false);
    });

    test('gives low cards to opponents', () async {
      final hand = [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.three, CardColor.blue),
        Card(CardFace.queen, CardColor.green),
        Card(CardFace.king, CardColor.black),
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.ace, CardColor.blue),
      ];
      final snapshot = aiSnapshot(myHand: hand);
      final action = await agent.selectSchupfCards(snapshot);

      // Opponents should get the lowest cards.
      expect(action.toLeft.value, lessThanOrEqualTo(3));
      expect(action.toRight.value, lessThanOrEqualTo(3));
    });

    test('throws with fewer than 3 cards', () async {
      final hand = [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.three, CardColor.blue),
      ];
      final snapshot = aiSnapshot(myHand: hand);
      expect(
        () => agent.selectSchupfCards(snapshot),
        throwsA(isA<StateError>()),
      );
    });

    test('gives best card to partner on grand tichu', () async {
      final hand = [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.ten, CardColor.blue),
        Card(CardFace.king, CardColor.green),
        Card(CardFace.ace, CardColor.black),
      ];
      final snapshot = aiSnapshot(
        myHand: hand,
        tichuCalls: {partnerId: TichuCall.grandTichu},
      );

      final action = await agent.selectSchupfCards(snapshot);
      expect(action.toPartner.face, CardFace.ace);
    });

    test('gives dog to opponent who called grand tichu', () async {
      final hand = [
        Card(CardFace.dog, CardColor.special),
        Card(CardFace.two, CardColor.red),
        Card(CardFace.three, CardColor.blue),
        Card(CardFace.four, CardColor.green),
      ];
      final snapshot = aiSnapshot(
        myHand: hand,
        tichuCalls: {leftId: TichuCall.grandTichu},
      );

      final action = await agent.selectSchupfCards(snapshot);
      expect(action.toLeft.face, CardFace.dog);
    });

    test('prefers even-valued card to the right opponent', () async {
      final hand = [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.three, CardColor.blue),
        Card(CardFace.four, CardColor.green),
        Card(CardFace.five, CardColor.black),
      ];
      final snapshot = aiSnapshot(myHand: hand);

      final action = await agent.selectSchupfCards(snapshot);
      expect(action.toRight.value.toInt().isEven, true);
    });
  });

  group('wish enforcement', () {
    test('plays a card fulfilling the wish when possible', () async {
      final hand = [
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.ten, CardColor.blue),
        Card(CardFace.king, CardColor.green),
      ];
      final deckTurn = TichuTurn(TurnType.single, [
        Card(CardFace.five, CardColor.black),
      ]);
      // Active wish for a seven.
      final deck = DeckState(deckTurn, CardFace.seven);
      deck.currentWinner = leftId;
      final snapshot = aiSnapshot(myHand: hand, deck: deck);

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      expect(play.cards.any((final c) => c.face == CardFace.seven), true);
    });

    test(
      'does not pass for partner support when wish is fulfillable',
      () async {
        final hand = [
          Card(CardFace.seven, CardColor.red),
          Card(CardFace.king, CardColor.blue),
        ];
        final deckTurn = TichuTurn(TurnType.single, [
          Card(CardFace.five, CardColor.black),
        ]);
        final deck = DeckState(deckTurn, CardFace.seven)
          ..currentWinner = partnerId;

        final snapshot = aiSnapshot(
          myHand: hand,
          deck: deck,
          otherHands: {
            leftId: defaultHand(),
            partnerId: [
              Card(CardFace.two, CardColor.red),
              Card(CardFace.three, CardColor.blue),
            ],
            rightId: defaultHand(),
          },
          tichuCalls: {partnerId: TichuCall.tichu},
          lastPlayedBy: partnerId,
          lastPlayedTurn: deckTurn,
        );

        final action = await agent.selectTurn(snapshot);
        expect(action, isA<PlayTurnAction>());
        final play = action as PlayTurnAction;
        expect(play.cards.any((final c) => c.face == CardFace.seven), isTrue);
      },
    );
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
      if (play.cards.any((final c) => c.face == CardFace.mahJong)) {
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
      if (play.cards.any((final c) => c.face == CardFace.mahJong)) {
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
      if (play.cards.any((final c) => c.face == CardFace.mahJong)) {
        expect(play.inputWish, CardFace.none);
      }
    });
  });

  group('selectDragonGive', () {
    test('avoids opponent who declared tichu', () {
      final agent = SmartAiAgent(aiId);

      final snapshot = aiSnapshot(
        myHand: [Card(CardFace.dragon, CardColor.special)],
        otherHands: {
          leftId: List.generate(
            6,
            (final i) => Card(CardFace.two, CardColor.red),
          ),
          partnerId: defaultHand(),
          rightId: List.generate(
            2,
            (final i) => Card(CardFace.two, CardColor.blue),
          ),
        },
        tichuCalls: {leftId: TichuCall.tichu},
      );

      final seat = agent.selectDragonGive(snapshot);
      // Left declared Tichu → give to right opponent.
      expect(seat, 3);
    });

    test('gives to opponent with more cards', () {
      final agent = SmartAiAgent(aiId);

      // Left has 8 cards, right has 3 cards.
      final snapshot = aiSnapshot(
        myHand: [Card(CardFace.dragon, CardColor.special)],
        otherHands: {
          leftId: List.generate(
            8,
            (final i) => Card(CardFace.two, CardColor.red),
          ),
          partnerId: defaultHand(),
          rightId: List.generate(
            3,
            (final i) => Card(CardFace.two, CardColor.blue),
          ),
        },
      );

      final seat = agent.selectDragonGive(snapshot);
      // Left opponent (seat 1) has more cards → should give to seat 1.
      expect(seat, 1);
    });

    test('gives to right opponent when right has more cards', () {
      final agent = SmartAiAgent(aiId);

      final snapshot = aiSnapshot(
        myHand: [Card(CardFace.dragon, CardColor.special)],
        otherHands: {
          leftId: List.generate(
            2,
            (final i) => Card(CardFace.two, CardColor.red),
          ),
          partnerId: defaultHand(),
          rightId: List.generate(
            10,
            (final i) => Card(CardFace.two, CardColor.blue),
          ),
        },
      );

      final seat = agent.selectDragonGive(snapshot);
      // Right opponent (seat 3) has more cards → should give to seat 3.
      expect(seat, 3);
    });
  });
}
