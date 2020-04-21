import 'package:tichu/view_model/tichu/card_utils.dart';
import 'package:tichu/view_model/tichu/tichu.dart';
import 'package:tichu/view_model/tichu/tichu_data.dart';

/// Returns true when the wish rules are being followed, false else.
bool obeyMahJong(DeckState deck, TichuTurn turn, List<Card> cards) {
  // We oautomatically bey in three cases:
  // - There is no wish.
  // - We cannot fullfill the wish.
  // - We fullfill the wish.
  if (deck.wish == null ||
      !cards.contains(deck.wish) ||
      turn.cards.contains(deck.wish) && validTurn(deck.turn, turn)) {
    return true;
  } else {
    // Player has wish card but it is not selected. Check if it is playable.
    return !canPlayWish(deck, cards);
  }
}

// Simple state machine that computes next wish based on previous wish and
// whether the wish has been satisfied or not.
Card computeNextWish(Card previousWish, CardSelection selection) {
  if (selection.wish != null) {
    return selection.wish;
  }
  if (selection.cards.contains(previousWish)) {
    return null;
  } else {
    return previousWish;
  }
}

// All functions below asume that cards contain the wish card.
bool canPlayWish(DeckState deck, List<Card> cards) {
  switch (deck.turn.type) {
    case TurnType.SINGLE:
      return canPlayWishOnSingle(deck, cards);
    case TurnType.PAIR:
      return canPlayWishOnPair(deck, cards);
      break;
    case TurnType.TRIPLET:
      return findTurnOnTriplet(deck, cards);
      break;
    case TurnType.PAIR_STRAIGHT:
      return findTurnOnPairStraight(deck, cards);
      break;
    case TurnType.FULL_HOUSE:
      return findTurnOnFullHouse(deck, cards);
      break;
    case TurnType.STRAIGHT_OF_5:
      return findTurnOnStraight(deck, cards);
      break;

    default:
      break;
  }

  return false;
}

bool canPlayWishOnSingle(DeckState deck, List<Card> cards) {
  return deck.wish.index > deck.turn.value;
}

bool canPlayWishOnPair(DeckState deck, List<Card> cards) {
  if (deck.turn.value >= deck.wish.index) {
    return false;
  }

  int wishCardCount = countOccurrence(cards, deck.wish);
  if (wishCardCount >= 2 || cards.contains(Card.PHOENIX)) {
    return true;
  } else {
    return false;
  }
}

bool findTurnOnPairStraight(DeckState deck, List<Card> cards) {
  return true;
}

bool findTurnOnTriplet(DeckState deck, List<Card> cards) {
  return true;
}

bool findTurnOnFullHouse(DeckState deck, List<Card> cards) {
  return true;
}

bool findTurnOnStraight(DeckState deck, List<Card> cards) {
  return true;
}
