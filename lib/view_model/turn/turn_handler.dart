import 'package:tichu/view_model/turn/find_turn.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';
import 'package:tichu/view_model/turn/wish_logic.dart';

class TurnHandler {
  List<Card> cards;
  DeckState currentDeck; // This should be stored on Firebase.

  // This is to be called each time the deck is updated.
  void updateDeck(DeckState newDeck) {
    currentDeck = newDeck;
  }

  // This is the main function. Deck can be null. selection cannot be empty
  void handleTurn(List<Card> cards, double phoenixValue, CardFace inputWish) {
    // Check if phoenix present and if yes, set its value.
    if (cards.any((element) => element.face == CardFace.PHOENIX)) {
      cards.sort(compareCards);
      cards.removeLast();
      if (cards.length >= 2) {
        cards.add(Card.phoenix(phoenixValue));
      } else if (currentDeck.turn.type == TurnType.SINGLE ||
          currentDeck.turn.type == TurnType.EMPTY) {
        cards.add(Card.phoenix(currentDeck.turn.value + 0.5));
      }
    }

    TichuTurn currentTurn = getTurn(cards);

    // Selected cards must form a valid turn.
    if (currentTurn == null) {
      return null;
    }

    // When mah jong is not obeyed, turn is invalid.
    if (!obeyMahJong(currentDeck, currentTurn, cards)) {
      return null;
    }

    if (!validTurn(currentDeck.turn, currentTurn)) {
      return null;
    }

    // The wish is either fulfilled or propagated to next deck state.
    currentDeck = DeckState(
        currentTurn, computeNextWish(currentDeck.wish, currentTurn, inputWish));
  }
}

bool validTurn(TichuTurn deck, TichuTurn turn) {
  // We can play any turn on an empty deck or dog.
  if (deck.type == TurnType.EMPTY || deck.type == TurnType.DOG) {
    return true;
  }

  // Standard case: play something higher.
  if (deck.type == turn.type) {
    if (deck.type == TurnType.STRAIGHT || deck.type == TurnType.PAIR_STRAIGHT) {
      return deck.cards.length == turn.cards.length && turn.value > deck.value;
    } else {
      return turn.value > deck.value;
    }
  }

  // Handle bombs
  if (deck.type != TurnType.BOMB && turn.type == TurnType.BOMB) {
    return true;
  }

  return false;
}
