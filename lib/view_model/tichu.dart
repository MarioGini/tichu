import 'package:tichu/view_model/find_turn.dart';
import 'package:tichu/view_model/tichu_data.dart';

// Wishes are ignored in this method.
bool validTurn(TichuTurn deck, TichuTurn turn) {
  // When deck is empty, any turn is valid.
  if (deck == null) {
    return true;
  }

  // Handle Mah Jong.
  if (deck.type == TurnType.SINGLE) {
    // TODO
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

// This is the main function. Deck can be null. selection cannot be empty
void handleTurn(TichuTurn deck, List<Card> selection, List<Card> allCards) {
  // TODO single phoenix needs information of deck to determine value.
  TichuTurn currentTurn = getTurn(selection);

  if (currentTurn != null && validTurn(deck, currentTurn)) {
    // 1. play cards locally

    // 2. update deck and who is to play next remotely. Update wish accordingly.

    // 3. notify all
  }
}
