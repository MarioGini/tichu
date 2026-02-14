import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn_rules_adapter.dart';
import 'package:tichu/game/turn/tichu_data.dart';

void main() {
  group('TurnRulesAdapter', () {
    final adapter = TurnRulesAdapter();

    test('detectTurn resolves a pair', () {
      final turn = adapter.detectTurn([
        Card(CardFace.five, CardColor.green),
        Card(CardFace.five, CardColor.red),
      ]);

      expect(turn.type, TurnType.pair);
      expect(turn.cards.length, 2);
    });

    test('tryApplyTurn returns valid deck for legal single on empty trick', () {
      final deck = DeckState(TichuTurn(TurnType.empty, []), CardFace.none);
      final card = Card(CardFace.nine, CardColor.black);

      final updated = adapter.tryApplyTurn(
        deck,
        [card],
        CardFace.none,
        hand: [card],
      );

      expect(updated.turn, TichuTurn(TurnType.single, [card]));
    });

    test('legalTurns returns playable options when turn is empty', () {
      final deck = DeckState(TichuTurn(TurnType.empty, []), CardFace.none);
      final hand = [
        Card(CardFace.ace, CardColor.green),
        Card(CardFace.king, CardColor.red),
      ];

      final legal = adapter.legalTurns(deck, hand);

      expect(legal, isNotEmpty);
      expect(legal.any((turn) => turn.type == TurnType.single), isTrue);
    });

    test('hasBomb identifies quartet bomb in hand', () {
      final bombHand = [
        Card(CardFace.ten, CardColor.green),
        Card(CardFace.ten, CardColor.red),
        Card(CardFace.ten, CardColor.blue),
        Card(CardFace.ten, CardColor.black),
      ];

      expect(adapter.hasBomb(bombHand), isTrue);
      expect(adapter.bombsInHand(bombHand), isNotEmpty);
    });

    test('firstPlayableBomb returns a bomb that can beat current turn', () {
      final deck = DeckState(
        TichuTurn(TurnType.single, [Card(CardFace.ace, CardColor.green)]),
        CardFace.none,
      );
      final hand = [
        Card(CardFace.ten, CardColor.green),
        Card(CardFace.ten, CardColor.red),
        Card(CardFace.ten, CardColor.blue),
        Card(CardFace.ten, CardColor.black),
      ];

      final playable = adapter.firstPlayableBomb(deck, hand);

      expect(playable, isNotNull);
      expect(playable!.type, TurnType.bomb);
    });
  });
}
