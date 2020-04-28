import 'package:tichu/view_model/tichu/tichu_data.dart';

// Returns null for invalid turns.
TichuTurn getTurn(List<Card> cards) {
  // Sort the cards accordingly.

  // When a single card is selected, we pass down current turn because phoenix
  // needs the info to determine its value.
  if (cards.length == 1) {
    checkSingle(cards[0]);
  }

  // Two cards can only be a PAIR.
  else if (cards.length == 2) {
    //return checkForPair(selection.cards);
  }

  // Three cards can only be a TRIPLET.
  else if (cards.length == 3) {
    //return checkForTriplet(selection.cards);
  }

  // Four cards can be a quartet bomb or PAIR_STRAIGHT.
  else if (cards.length == 4) {
    //return checkForQuartet(selection.cards);
  }

  // Five cards can be full house or straight.

  return null;
}

// Utility functions to determine turn type

// A single card can be either of turn type dog, dragon or single. When it is a
// single phoenix, we need the current turn value to determine the phoenix
// value.
TichuTurn checkSingle(Card card) {
  if (card.face == CardFace.DOG) {
    return TichuTurn(TurnType.DOG, [card]);
  } else if (card.face == CardFace.DRAGON) {
    return TichuTurn(TurnType.DRAGON, [card]);
  }
  return TichuTurn(TurnType.SINGLE, [card]);
}

TichuTurn checkForPair(List<Card> cards) {
  TichuTurn possibleTurn;

  if (cards[0].value == cards[1].value) {
    possibleTurn = TichuTurn(TurnType.PAIR, cards);
  }

  return possibleTurn;
}

TichuTurn checkForTriplet(List<Card> cards) {
  TichuTurn possibleTurn;

  if ((cards[0].value == cards[1].value) &&
      (cards[1].value == cards[2].value)) {
    possibleTurn = TichuTurn(TurnType.TRIPLET, cards);
  }

  return possibleTurn;
}

// Phoenix does not count here.
TichuTurn checkForQuartett(List<Card> cards) {
  return null;
}
