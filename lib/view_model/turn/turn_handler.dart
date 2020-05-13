import 'find_turn.dart';
import 'tichu_data.dart';
import 'wish_logic.dart';

class TurnHandler {
  // This is the main function. Deck can be null. selection cannot be empty
  DeckState handleTurn(
      DeckState currentDeck, List<Card> cards, CardFace inputWish) {
    var currentTurn = getTurn(cards);

    // Selected cards must form a valid turn.
    if (currentTurn == null) {
      return null; // TODO inform user
    }

    // When mah jong is not obeyed, turn is invalid.
    if (mahJong(currentDeck, currentTurn, cards)) {
      return null;
    }

    if (!validTurn(currentDeck.turn, currentTurn)) {
      return null;
    }

    // The wish is either fulfilled or propagated to next deck state.
    return DeckState(
        currentTurn, computeNextWish(currentDeck.wish, currentTurn, inputWish));
  }
}

bool validTurn(TichuTurn deck, TichuTurn turn) {
  // We can play any turn on an empty deck or dog.
  if (deck.type == TurnType.empty || deck.type == TurnType.dog) {
    return true;
  }

  // We can only play a turn of the same type.
  if (deck.type == turn.type) {
    // For straights and pair straights, we additionally require same length.
    if (deck.type == TurnType.straight || deck.type == TurnType.pairStraight) {
      return deck.cards.length == turn.cards.length && turn.value > deck.value;
    } else {
      return turn.value > deck.value;
    }
  }

  // Handle bombs
  if (deck.type != TurnType.bomb && turn.type == TurnType.bomb) {
    return true;
  }

  return false;
}
