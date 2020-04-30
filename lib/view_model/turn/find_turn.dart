import 'package:tichu/view_model/turn/card_utils.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';

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
    // Five cards can be a full house or a straight.
    detectedTurn = checkFives(cards);
  } else {
    // Big turns can be straights or pair straights.
    detectedTurn = checkBigTurns(cards);
  }

  return detectedTurn;
}

// A single card can be either of turn type dog, dragon or single.
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

  if (cards.length == 2 && cards[0].value == cards[1].value) {
    possibleTurn = TichuTurn(TurnType.PAIR, cards);
  }

  return possibleTurn;
}

TichuTurn checkForTriplet(List<Card> cards) {
  TichuTurn possibleTurn;

  if (cards.length == 3 &&
      cards[0].value == cards[1].value &&
      cards[1].value == cards[2].value) {
    possibleTurn = TichuTurn(TurnType.TRIPLET, cards);
  }

  return possibleTurn;
}

TichuTurn checkForQuartet(List<Card> cards) {
  TichuTurn possibleTurn;

  if (cards.length == 4 &&
      cards.every((element) => element.face != CardFace.PHOENIX) &&
      cards[0].value == cards[1].value &&
      cards[1].value == cards[2].value &&
      cards[2].value == cards[3].value) {
    // When all four cards have the same value and no phoenix is involved, we
    // have a quartet bomb.
    possibleTurn = TichuTurn(TurnType.BOMB, cards);
  } else if (isPairStraight(cards)) {
    possibleTurn = TichuTurn(TurnType.PAIR_STRAIGHT, cards);
  }

  return possibleTurn;
}

TichuTurn checkFives(List<Card> cards) {
  TichuTurn possibleTurn;

  if (isFullHouse(cards)) {
    possibleTurn = TichuTurn(TurnType.FULL_HOUSE, cards);
  } else if (isStraight(cards)) {
    if (uniformColor(cards)) {
      possibleTurn = TichuTurn(TurnType.BOMB, cards);
    } else {
      possibleTurn = TichuTurn(TurnType.STRAIGHT, cards);
    }
  }

  return possibleTurn;
}

// For selections with six or more cards. That can only be a straight or pair
// straight. Uniformly colored straights are bombs.
TichuTurn checkBigTurns(List<Card> cards) {
  TichuTurn possibleTurn;

  if (isStraight(cards)) {
    if (uniformColor(cards)) {
      possibleTurn = TichuTurn(TurnType.BOMB, cards);
    } else {
      possibleTurn = TichuTurn(TurnType.STRAIGHT, cards);
    }
  } else if (isPairStraight(cards)) {
    possibleTurn = TichuTurn(TurnType.PAIR_STRAIGHT, cards);
  }

  return possibleTurn;
}
