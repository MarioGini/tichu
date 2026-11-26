import 'package:tichu/game/turn/find_turn.dart';
import 'package:tichu/game/turn/move_generator.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/turn_handler.dart';
import 'package:tichu/game/turn/utils/bomb_utils.dart';

class TurnRulesAdapter {
  final TurnHandler _turnHandler;

  TurnRulesAdapter({TurnHandler? turnHandler})
    : _turnHandler = turnHandler ?? TurnHandler();

  TichuTurn detectTurn(List<Card> cards) => getTurn(List<Card>.from(cards));

  DeckState tryApplyTurn(
    DeckState deck,
    List<Card> cards,
    CardFace inputWish, {
    List<Card>? hand,
  }) => _turnHandler.handleTurn(
    deck,
    List<Card>.from(cards),
    inputWish,
    hand: hand,
  );

  List<TichuTurn> legalTurns(DeckState deck, List<Card> hand) =>
      generateLegalTurns(deck, List<Card>.from(hand));

  List<TichuTurn> bombsInHand(List<Card> hand) =>
      getBombs(List<Card>.from(hand));

  TichuTurn? firstPlayableBomb(DeckState deck, List<Card> hand) {
    for (final bomb in bombsInHand(hand)) {
      final updated = tryApplyTurn(deck, bomb.cards, CardFace.none, hand: hand);
      if (updated.turn != TichuTurn.invalid()) {
        return bomb;
      }
    }
    return null;
  }
}
