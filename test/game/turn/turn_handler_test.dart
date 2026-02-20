import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/turn_handler.dart';

void main() {
  group('validTurn', () {
    test('dragonOnSingleTest', () {
      final deckTurn = TichuTurn(TurnType.single, [
        Card(CardFace.ten, CardColor.red),
      ]);
      final currentTurn = TichuTurn(TurnType.single, [
        Card(CardFace.dragon, CardColor.special),
      ]);

      expect(validTurn(deckTurn, currentTurn), true);
    });
    test('bombPairTest', () {
      final deckTurn = TichuTurn(TurnType.pair, [
        Card(CardFace.ten, CardColor.red),
        Card(CardFace.ten, CardColor.blue),
      ]);
      final currentTurn = TichuTurn(TurnType.bomb, [
        Card(CardFace.eight, CardColor.red),
        Card(CardFace.eight, CardColor.black),
        Card(CardFace.eight, CardColor.green),
        Card(CardFace.eight, CardColor.blue),
      ]);

      expect(validTurn(deckTurn, currentTurn), true);
    });
  });

  group('handleTurn wish enforcement', () {
    test('rejects play that ignores fulfillable wish', () {
      final handler = TurnHandler();
      final deck = DeckState(
        TichuTurn(TurnType.single, [Card(CardFace.four, CardColor.blue)]),
        CardFace.ace,
      );
      final hand = <Card>[
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.six, CardColor.green),
      ];
      final selected = <Card>[Card(CardFace.six, CardColor.green)];

      final updated = handler.handleTurn(
        deck,
        selected,
        CardFace.none,
        hand: hand,
      );

      expect(updated.turn, TichuTurn.InvalidTurn());
    });

    test('allows play when wish cannot be fulfilled', () {
      final handler = TurnHandler();
      final deck = DeckState(
        TichuTurn(TurnType.single, [Card(CardFace.king, CardColor.black)]),
        CardFace.four,
      );
      final hand = <Card>[
        Card(CardFace.four, CardColor.red),
        Card(CardFace.ace, CardColor.green),
      ];
      final selected = <Card>[Card(CardFace.ace, CardColor.green)];

      final updated = handler.handleTurn(
        deck,
        selected,
        CardFace.none,
        hand: hand,
      );

      expect(updated.turn, isNot(TichuTurn.InvalidTurn()));
    });
  });

  group('handleTurn recognizes triplet/full house plays', () {
    test('accepts triplet on empty deck', () {
      final handler = TurnHandler();
      final deck = DeckState(TichuTurn(TurnType.empty, const []), CardFace.none);
      final selected = <Card>[
        Card(CardFace.queen, CardColor.red),
        Card(CardFace.queen, CardColor.blue),
        Card(CardFace.queen, CardColor.green),
      ];

      final updated = handler.handleTurn(
        deck,
        selected,
        CardFace.none,
        hand: List<Card>.from(selected),
      );

      expect(updated.turn, isNot(TichuTurn.InvalidTurn()));
      expect(updated.turn.type, TurnType.triplet);
    });

    test('accepts full house on empty deck', () {
      final handler = TurnHandler();
      final deck = DeckState(TichuTurn(TurnType.empty, const []), CardFace.none);
      final selected = <Card>[
        Card(CardFace.queen, CardColor.red),
        Card(CardFace.queen, CardColor.blue),
        Card(CardFace.queen, CardColor.green),
        Card(CardFace.king, CardColor.red),
        Card(CardFace.king, CardColor.blue),
      ];

      final updated = handler.handleTurn(
        deck,
        selected,
        CardFace.none,
        hand: List<Card>.from(selected),
      );

      expect(updated.turn, isNot(TichuTurn.InvalidTurn()));
      expect(updated.turn.type, TurnType.fullHouse);
    });

    test('accepts pair with phoenix on empty deck', () {
      final handler = TurnHandler();
      final deck = DeckState(TichuTurn(TurnType.empty, const []), CardFace.none);
      final selected = <Card>[
        Card(CardFace.queen, CardColor.red),
        const Card.phoenix(2),
      ];

      final updated = handler.handleTurn(
        deck,
        selected,
        CardFace.none,
        hand: List<Card>.from(selected),
      );

      expect(updated.turn, isNot(TichuTurn.InvalidTurn()));
      expect(updated.turn.type, TurnType.pair);
    });
  });

  group('handleTurn phoenix single behavior', () {
    test('phoenix single beats ace', () {
      final handler = TurnHandler();
      final deck = DeckState(
        TichuTurn(TurnType.single, [Card(CardFace.ace, CardColor.blue)]),
        CardFace.none,
      );
      final selected = <Card>[Card(CardFace.phoenix, CardColor.special)];

      final updated = handler.handleTurn(
        deck,
        selected,
        CardFace.none,
        hand: List<Card>.from(selected),
      );

      expect(updated.turn, isNot(TichuTurn.InvalidTurn()));
      expect(updated.turn.type, TurnType.single);
      expect(updated.turn.value, deck.turn.value + 0.5);
    });

    test('phoenix single cannot beat dragon', () {
      final handler = TurnHandler();
      final deck = DeckState(
        TichuTurn(TurnType.single, [Card(CardFace.dragon, CardColor.special)]),
        CardFace.none,
      );
      final selected = <Card>[Card(CardFace.phoenix, CardColor.special)];

      final updated = handler.handleTurn(
        deck,
        selected,
        CardFace.none,
        hand: List<Card>.from(selected),
      );

      expect(updated.turn, TichuTurn.InvalidTurn());
    });
  });
}
