enum Card {
  TWO,
  THREE,
  FOUR,
  FIVE,
  SIX,
  SEVEN,
  EIGHT,
  NINE,
  TEN,
  JACK,
  QUEEN,
  KING,
  ACE,
  DRAGON,
  DOG,
  MAH_JONG,
  PHOENIX
}

enum Color { BLACK, GREEN, RED, BLUE }

enum TurnType {
  SINGLE,
  PAIR,
  PAIR_STRAIGHT,
  TRIPLET,
  FULL_HOUSE,
  STRAIGHT_OF_5,
  STRAIGHT_OF_6,
  STRAIGHT_OF_7,
  STRAIGHT_OF_8,
  STRAIGHT_OF_9,
  STRAIGHT_OF_10,
  STRAIGHT_OF_11,
  STRAIGHT_OF_12,
  STRAIGHT_OF_13,
  STRAIGHT_OF_14,
  DRAGON,
  DOG,
  MAH_JONG,
  BOMB, // Either four of a kind or a straight bomb
}

class TichuTurn {
  final TurnType type;
  final double value;
  int wishValue; // set to 0 when no wish is present.

  TichuTurn(this.type, this.value);
}

// Wishes are ignored in this method.
bool validTurn(TichuTurn deck, TichuTurn turn) {
  // When deck is empty, any turn is valid.
  if (deck == null) {
    return true;
  }

  // Handle Mah Jong.
  if (deck.type == TurnType.MAH_JONG) {
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

// Returns null for invalid turns.
TichuTurn getTurn(List<Card> turn) {
  // Sort the cards accordingly. All special cards are at the end.

  // Handle singles and derivatives.
  if (turn.length == 1) {
    checkSingle(turn[0]);
  }

  // Two cards can only be a PAIR.
  else if (turn.length == 2) {
    return checkForPair(turn);
  }

  // Three cards can only be a TRIPLET.
  else if (turn.length == 3) {
    return checkForTriplet(turn);
  }

  // Four cards can be a quartett bomb or PAIR_STRAIGHT.
  else if (turn.length == 4) {
    return checkForQuartett(turn);
  }

  // Five cards can be full house or straight.

  return null;
}

// Utility functions to determine turn type

TichuTurn checkSingle(Card card) {
  switch (card) {
    case Card.MAH_JONG:
      // TODO in that case, handle the wish value.
      TichuTurn currentTurn = TichuTurn(TurnType.MAH_JONG, 0);
      currentTurn.wishValue = 3;
      return currentTurn;
      break;
    case Card.PHOENIX:
      // TODO obtain previous card value.
      return TichuTurn(TurnType.SINGLE, 4.5);
      break;
    case Card.DRAGON:
      return TichuTurn(TurnType.DRAGON, 0);
      break;
    default:
      break;
  }
  return null;
}

TichuTurn checkForPair(List<Card> cards) {
  if (isSpecialCard(cards)) {
    return null;
  }
  // is sorted, so only second card can be phoenix.
  else if (cards[0] == cards[1] || cards[1] == Card.PHOENIX) {
    return TichuTurn(
      TurnType.PAIR,
    );
  } else {
    return null;
  }
}

TichuTurn checkForTriplet(List<Card> cards) {
  if (isSpecialCard(cards)) {
    return null;
  }
  return null;
}

// Phoenix does not count here.
TichuTurn checkForQuartett(List<Card> cards) {
  if (isSpecialCard(cards)) {
    return null;
  }
}

// Special cards are dragon, mah jong, dog.
bool isSpecialCard(List<Card> cards) {
  bool atLeastOneSpecialCard = false;

  cards.forEach((card) {
    switch (card) {
      case Card.MAH_JONG:
        atLeastOneSpecialCard = true;
        break;
      case Card.DRAGON:
        atLeastOneSpecialCard = true;
        break;
      case Card.DOG:
        atLeastOneSpecialCard = true;
        break;
      default:
    }
  });

  return atLeastOneSpecialCard;
}

// converts enum into double value.
// TODO overload for cases with phoenix and other card.
double getValueOfCard(Card card) {}
