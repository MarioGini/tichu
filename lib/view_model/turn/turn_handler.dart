import 'package:tichu/view_model/turn/find_turn.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';
import 'package:tichu/view_model/turn/wish_logic.dart';

class TurnHandler {
  DeckState handleTurn(
    DeckState currentDeck,
    List<Card> selectedCards,
    CardFace inputWish, {
    List<Card>? hand,
  }) {
    final normalizedCards = _normalizePhoenixSingle(currentDeck, selectedCards);
    var currentTurn = getTurn(normalizedCards);
    final handCards = hand ?? selectedCards;

    // Selected cards must form a valid turn.
    if (currentTurn == TichuTurn.InvalidTurn()) {
      return DeckState.Invalid(); // TODO inform user
    }

    // When mah jong is not obeyed, turn is invalid.
    if (mahJong(currentDeck, currentTurn, handCards)) {
      return DeckState.Invalid();
    }

    if (!validTurn(currentDeck.turn, currentTurn)) {
      return DeckState.Invalid();
    }

    // The wish is either fulfilled or propagated to next deck state.
    return DeckState(
      currentTurn,
      computeNextWish(currentDeck.wish, currentTurn, inputWish),
    );
  }
}

List<Card> _normalizePhoenixSingle(
  DeckState currentDeck,
  List<Card> selectedCards,
) {
  if (selectedCards.length != 1) {
    return selectedCards;
  }

  final card = selectedCards.first;
  if (card.face != CardFace.phoenix) {
    return selectedCards;
  }

  if (card.value != Card.getValue(CardFace.phoenix)) {
    return selectedCards;
  }

  final deckTurn = currentDeck.turn;
  if (deckTurn.type == TurnType.single &&
      deckTurn.cards.isNotEmpty &&
      deckTurn.cards.first.face == CardFace.dragon) {
    return selectedCards;
  }

  final phoenixValue =
      deckTurn.type == TurnType.single && deckTurn.cards.isNotEmpty
      ? deckTurn.value + 0.5
      : 1.5;
  return [Card.phoenix(phoenixValue)];
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
