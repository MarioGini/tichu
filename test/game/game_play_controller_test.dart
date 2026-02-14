import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_play_controller.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import '../utils/test_game_fixtures.dart';

void main() {
  group('GamePlayController', () {
    final controller = GamePlayController();

    test('resolveSelectedTurn returns null for empty selection', () {
      final snapshot = buildPlayerSnapshot(currentPlayerId: testHumanId);

      final resolved = controller.resolveSelectedTurn(
        snapshot: snapshot,
        selectedCards: const [],
        hand: snapshot.hand,
      );

      expect(resolved, isNull);
    });

    test('resolveSelectedTurn returns turn for legal selected single', () {
      final card = Card(CardFace.ace, CardColor.green);
      final snapshot = buildPlayerSnapshot(
        currentPlayerId: testHumanId,
        hand: [card],
        deck: DeckState(TichuTurn(TurnType.empty, []), CardFace.none),
      );

      final resolved = controller.resolveSelectedTurn(
        snapshot: snapshot,
        selectedCards: [card],
        hand: snapshot.hand,
      );

      expect(resolved, isNotNull);
      expect(resolved!.type, TurnType.single);
    });

    test('canPlaySelected is false when not human turn', () {
      final card = Card(CardFace.ace, CardColor.green);
      final snapshot = buildPlayerSnapshot(
        currentPlayerId: testOpponentLeftId,
        hand: [card],
      );

      final canPlay = controller.canPlaySelected(
        snapshot: snapshot,
        humanId: testHumanId,
        hand: snapshot.hand,
        selectedCards: [card],
        schupfAckPending: false,
      );

      expect(canPlay, isFalse);
    });

    test('canPlaySelected is true for legal selected turn on human turn', () {
      final card = Card(CardFace.ace, CardColor.green);
      final snapshot = buildPlayerSnapshot(
        currentPlayerId: testHumanId,
        hand: [card],
        deck: DeckState(TichuTurn(TurnType.empty, []), CardFace.none),
      );

      final canPlay = controller.canPlaySelected(
        snapshot: snapshot,
        humanId: testHumanId,
        hand: snapshot.hand,
        selectedCards: [card],
        schupfAckPending: false,
      );

      expect(canPlay, isTrue);
    });

    test('canPlayAny is false when no legal response exists', () {
      final snapshot = buildPlayerSnapshot(
        currentPlayerId: testHumanId,
        hand: [Card(CardFace.two, CardColor.green)],
        deck: DeckState(
          TichuTurn(TurnType.single, [Card(CardFace.dragon, CardColor.special)]),
          CardFace.none,
        ),
      );

      final canPlayAny = controller.canPlayAny(
        snapshot: snapshot,
        humanId: testHumanId,
        hand: snapshot.hand,
        schupfAckPending: false,
      );

      expect(canPlayAny, isFalse);
    });

    test('canEnableBomb is false when deck empty and not human turn', () {
      final bombHand = [
        Card(CardFace.ten, CardColor.green),
        Card(CardFace.ten, CardColor.red),
        Card(CardFace.ten, CardColor.blue),
        Card(CardFace.ten, CardColor.black),
      ];
      final snapshot = buildPlayerSnapshot(
        currentPlayerId: testOpponentLeftId,
        hand: bombHand,
        deck: DeckState(TichuTurn(TurnType.empty, []), CardFace.none),
      );

      final enabled = controller.canEnableBomb(
        snapshot: snapshot,
        humanId: testHumanId,
        hand: snapshot.hand,
      );

      expect(enabled, isFalse);
    });

    test('canEnableBomb is true when human can slam a bomb', () {
      final bombHand = [
        Card(CardFace.ten, CardColor.green),
        Card(CardFace.ten, CardColor.red),
        Card(CardFace.ten, CardColor.blue),
        Card(CardFace.ten, CardColor.black),
      ];
      final snapshot = buildPlayerSnapshot(
        currentPlayerId: testHumanId,
        hand: bombHand,
      );

      final enabled = controller.canEnableBomb(
        snapshot: snapshot,
        humanId: testHumanId,
        hand: snapshot.hand,
      );

      expect(enabled, isTrue);
    });

    test('shouldAutoSelectFinisher is true when full hand is a legal turn', () {
      final fullHouseHand = [
        Card(CardFace.five, CardColor.green),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.king, CardColor.blue),
        Card(CardFace.king, CardColor.green),
      ];
      final snapshot = buildPlayerSnapshot(
        currentPlayerId: testHumanId,
        hand: fullHouseHand,
        deck: DeckState(TichuTurn(TurnType.empty, []), CardFace.none),
      );

      final shouldAutoSelect = controller.shouldAutoSelectFinisher(
        snapshot: snapshot,
        humanId: testHumanId,
        hand: snapshot.hand,
        schupfAckPending: false,
        hasSelectedCards: false,
      );

      expect(shouldAutoSelect, isTrue);
    });

    test('shouldAutoSelectFinisher is false when selection already exists', () {
      final snapshot = buildPlayerSnapshot(
        currentPlayerId: testHumanId,
        hand: [Card(CardFace.ace, CardColor.green)],
      );

      final shouldAutoSelect = controller.shouldAutoSelectFinisher(
        snapshot: snapshot,
        humanId: testHumanId,
        hand: snapshot.hand,
        schupfAckPending: false,
        hasSelectedCards: true,
      );

      expect(shouldAutoSelect, isFalse);
    });
  });
}
