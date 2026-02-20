import 'package:tichu/game/turn/find_turn.dart';
import 'package:tichu/game/turn/move_generator.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/turn_handler.dart';
import 'package:tichu/game/turn/utils/bomb_utils.dart';

class TurnRulesAdapter {
  final TurnHandler _turnHandler;

  TurnRulesAdapter({final TurnHandler? turnHandler})
    : _turnHandler = turnHandler ?? TurnHandler();

  TichuTurn detectTurn(final List<Card> cards) => getTurn(List<Card>.from(cards));

  DeckState tryApplyTurn(
    final DeckState deck,
    final List<Card> cards,
    final CardFace inputWish, {
    final List<Card>? hand,
  }) => _turnHandler.handleTurn(
      deck,
      List<Card>.from(cards),
      inputWish,
      hand: hand,
    );

  List<TichuTurn> legalTurns(final DeckState deck, final List<Card> hand) => generateLegalTurns(deck, List<Card>.from(hand));

  List<TichuTurn> bombsInHand(final List<Card> hand) => getBombs(List<Card>.from(hand));

  bool hasBomb(final List<Card> hand) => hasBombInHand(hand);

  TichuTurn? firstPlayableBomb(final DeckState deck, final List<Card> hand) {
    for (final bomb in bombsInHand(hand)) {
      final updated = tryApplyTurn(deck, bomb.cards, CardFace.none, hand: hand);
      if (updated.turn != TichuTurn.InvalidTurn()) {
        return bomb;
      }
    }
    return null;
  }
}
