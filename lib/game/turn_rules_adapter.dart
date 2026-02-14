import 'package:tichu/game/turn/find_turn.dart';
import 'package:tichu/game/turn/move_generator.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/turn_handler.dart';
import 'package:tichu/game/turn/utils/bomb_utils.dart';

class TurnRulesAdapter {
  final TurnHandler _turnHandler;

  TurnRulesAdapter({TurnHandler? turnHandler})
    : _turnHandler = turnHandler ?? TurnHandler();

  TichuTurn detectTurn(List<Card> cards) {
    return getTurn(List<Card>.from(cards));
  }

  DeckState tryApplyTurn(
    DeckState deck,
    List<Card> cards,
    CardFace inputWish, {
    List<Card>? hand,
  }) {
    return _turnHandler.handleTurn(
      deck,
      List<Card>.from(cards),
      inputWish,
      hand: hand,
    );
  }

  List<TichuTurn> legalTurns(DeckState deck, List<Card> hand) {
    return generateLegalTurns(deck, List<Card>.from(hand));
  }

  List<TichuTurn> bombsInHand(List<Card> hand) {
    return getBombs(List<Card>.from(hand));
  }

  bool hasBomb(List<Card> hand) {
    return hasBombInHand(hand);
  }

  TichuTurn? firstPlayableBomb(DeckState deck, List<Card> hand) {
    for (final bomb in bombsInHand(hand)) {
      final updated = tryApplyTurn(deck, bomb.cards, CardFace.none, hand: hand);
      if (updated.turn != TichuTurn.InvalidTurn()) {
        return bomb;
      }
    }
    return null;
  }
}
