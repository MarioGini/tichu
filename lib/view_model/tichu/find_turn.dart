import 'package:tichu/view_model/tichu/tichu_data.dart';

// Returns null for invalid turns.
TichuTurn getTurn(CardSelection selection) {
  // Sort the cards accordingly.

  // Handle singles and derivatives.
  if (selection.cards.length == 1) {
    //checkSingle(selection.cards[0]);
  }

  // Two cards can only be a PAIR.
  else if (selection.cards.length == 2) {
    //return checkForPair(selection.cards);
  }

  // Three cards can only be a TRIPLET.
  else if (selection.cards.length == 3) {
    //return checkForTriplet(selection.cards);
  }

  // Four cards can be a quartett bomb or PAIR_STRAIGHT.
  else if (selection.cards.length == 4) {
    //return checkForQuartett(selection.cards);
  }

  // Five cards can be full house or straight.

  return null;
}

// Utility functions to determine turn type

TichuTurn checkSingle(Card card) {
  if (!isSpecialCard([card])) {
    return TichuTurn(TurnType.SINGLE, card.index.toDouble(), {card: 1});
  }

  switch (card) {
    case Card.MAH_JONG:
      // TODO in that case, handle the wish value.
      TichuTurn currentTurn = TichuTurn(TurnType.SINGLE, 1, {card: 1});
      return currentTurn;
      break;
    case Card.PHOENIX:
      // TODO obtain previous card value.
      return TichuTurn(TurnType.SINGLE, 4.5, {card: 1});
      break;
    case Card.DRAGON:
      return TichuTurn(TurnType.DRAGON, 0, {card: 1});
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
    //return TichuTurn(TurnType.PAIR, 2, cards);
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

  return null;
}

// converts enum into double value.
// TODO overload for cases with phoenix and other card.
double getValueOfCard(Card card) {
  return 0.0;
}

// Special cards are dragon, mah jong, dog, phoenix.
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
      case Card.PHOENIX:
        atLeastOneSpecialCard = true;
        break;
      default:
        break;
    }
  });

  return atLeastOneSpecialCard;
}
