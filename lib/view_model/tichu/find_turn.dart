import 'package:tichu/view_model/tichu/card_utils.dart';
import 'package:tichu/view_model/tichu/tichu_data.dart';

// Returns null for invalid turns. The phoenix has already a dedicated value.
TichuTurn getTurn(List<Card> cards) {
  TichuTurn detectedTurn;

  cards.sort(compareCards);

  if (cards.length == 1) {
    // Single card is of type single, dragon or dog.
    detectedTurn = checkSingle(cards[0]);
  } else if (cards.length == 2) {
    // Two cards can only be a pair.
    detectedTurn = checkForPair(cards);
  } else if (cards.length == 3) {
    // Three cards can only be a triplet.
    detectedTurn = checkForTriplet(cards);
  } else if (cards.length == 4) {
    // Four cards can be a quartet bomb or pair straight.
    detectedTurn = checkForQuartet(cards);
  } else if (cards.length == 5) {
    // Check for full house.
    detectedTurn = checkFives(cards);
  } else {
    detectedTurn = checkBigTurns(cards);
  }

  return detectedTurn;
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

// Input must be a list of length 2.
TichuTurn checkForPair(List<Card> cards) {
  TichuTurn possibleTurn;

  if (cards[0].value == cards[1].value) {
    possibleTurn = TichuTurn(TurnType.PAIR, cards);
  }

  return possibleTurn;
}

// Input must be a list of length 3.
TichuTurn checkForTriplet(List<Card> cards) {
  TichuTurn possibleTurn;

  if (cards[0].value == cards[1].value && cards[1].value == cards[2].value) {
    possibleTurn = TichuTurn(TurnType.TRIPLET, cards);
  }

  return possibleTurn;
}

// Input must be a list of length 4 and sorted.
TichuTurn checkForQuartet(List<Card> cards) {
  TichuTurn possibleTurn;

  if (cards.where((element) => element.face == CardFace.PHOENIX).length == 0 &&
      cards[0].value == cards[1].value &&
      cards[1].value == cards[2].value &&
      cards[2].value == cards[3].value) {
    // When all four cards have the same value and no phoenix is involved, we
    // have a quartet bomb.
    possibleTurn = TichuTurn(TurnType.BOMB, cards);
  } else if (cards[0].value == cards[1].value &&
      cards[2].value == cards[3].value &&
      cards[0].value == cards[2].value + 1.0) {
    // When we have two pairs, we have a pair straight.
    possibleTurn = TichuTurn(TurnType.PAIR_STRAIGHT, cards);
  }
  return possibleTurn;
}

// List must have length 5 and be sorted
TichuTurn checkFives(List<Card> cards) {
  TichuTurn possibleTurn;

  // Look for a full house
  if (cards.length == 5) {
    possibleTurn = TichuTurn(TurnType.FULL_HOUSE, cards);
  } else if (areOrdered(cards)) {
    // TODO could also be straight bomb.
    possibleTurn = TichuTurn(TurnType.STRAIGHT, cards);
  }

  return possibleTurn;
}

// For selections with six or more cards.
TichuTurn checkBigTurns(List<Card> cards) {
  TichuTurn possibleTurn;

  if (areOrdered(cards)) {
    if (uniformColor(cards)) {
      possibleTurn = TichuTurn(TurnType.BOMB, cards);
    } else {
      possibleTurn = TichuTurn(TurnType.STRAIGHT, cards);
    }
  } else if (cards.length % 2 == 0) {
    // TODO need further criteria.
    possibleTurn = TichuTurn(TurnType.PAIR_STRAIGHT, cards);
  }

  return possibleTurn;
}
