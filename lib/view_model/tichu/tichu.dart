import 'package:tichu/view_model/tichu/find_turn.dart';
import 'package:tichu/view_model/tichu/tichu_data.dart';
import 'package:tichu/view_model/tichu/wish_logic.dart';

// This is the main function. Deck can be null. selection cannot be empty
DeckState handleTurn(
    DeckState deck, CardSelection selection, List<Card> allCards) {
  // TODO single phoenix needs information of deck to determine value.
  TichuTurn currentTurn = getTurn(selection);

  // Selected cards must form a valid turn.
  if (currentTurn == null) {
    return null;
  }

  // When mah jong is not obeyed, turn is invalid.
  if (!obeyMahJong(deck, currentTurn, allCards)) {
    return null;
  }

  // The wish is either fullfilled or propagated to next deck state.

  if (!validTurn(deck.turn, currentTurn)) {
    return null;
  }

  return DeckState(currentTurn, computeNextWish(deck.wish, selection));
}

bool validTurn(TichuTurn deck, TichuTurn turn) {
  // When deck is empty, any turn is valid.
  if (deck == null) {
    return true;
  }

  // Standard case: play something higher.
  if (deck.type == turn.type && turn.value > deck.value) {
    return true;
  }

  // Handle bombs
  if (deck.type != TurnType.BOMB && turn.type == TurnType.BOMB) {
    return true;
  }

  return false;
}
