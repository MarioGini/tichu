import 'package:tichu/view_model/tichu/card_utils.dart';
import 'package:tichu/view_model/tichu/tichu.dart';
import 'package:tichu/view_model/tichu/tichu_data.dart';

/// Returns true when the wish rules are being followed, false else.
bool obeyMahJong(DeckState deck, TichuTurn turn, Map<Card, int> cards) {
  // We automatically bey in three cases:
  // - There is no wish.
  // - We cannot fulfill the wish.
  // - We fulfill the wish.
  if (deck.wish == null ||
      !cards.containsKey(deck.wish) ||
      turn.cards.containsKey(deck.wish) && validTurn(deck.turn, turn)) {
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
  if (selection.cards.containsKey(previousWish)) {
    return null;
  } else {
    return previousWish;
  }
}

// All functions below assume that cards contain the wish card.
bool canPlayWish(DeckState deck, Map<Card, int> cards) {
  switch (deck.turn.type) {
    case TurnType.SINGLE:
      return canPlayWishOnSingle(deck, cards);
    case TurnType.PAIR:
      return canPlayWishOnPair(deck, cards);
      break;
    case TurnType.TRIPLET:
      return canPlayWishOnTriplet(deck, cards);
      break;
    case TurnType.PAIR_STRAIGHT:
      return findTurnOnPairStraight(deck, cards);
      break;
    case TurnType.FULL_HOUSE:
      return canPlayWishOnFullHouse(deck, cards);
      break;
    case TurnType.STRAIGHT_OF_5:
      return findTurnOnStraight(deck, cards);
      break;

    default:
      break;
  }

  return false;
}

bool canPlayWishOnSingle(DeckState deck, Map<Card, int> cards) {
  return canPlayCard(deck.wish, deck.turn.value);
}

bool canPlayWishOnPair(DeckState deck, Map<Card, int> cards) {
  if (canPlayCard(deck.wish, deck.turn.value)) {
    if (cards[deck.wish] >= 2 || cards.containsKey(Card.PHOENIX)) {
      return true;
    } else {
      return false;
    }
  }
  return false;
}

bool findTurnOnPairStraight(DeckState deck, Map<Card, int> cards) {
  return true;
}

bool canPlayWishOnTriplet(DeckState deck, Map<Card, int> cards) {
  if (canPlayCard(deck.wish, deck.turn.value)) {
    if (cards[deck.wish] >= 3 ||
        (cards[deck.wish] >= 2 && cards.containsKey(Card.PHOENIX))) {
      return true;
    } else {
      return false;
    }
  }
  return false;
}

bool canPlayWishOnFullHouse(DeckState deck, Map<Card, int> cards) {
  // Wish needs to be pair/triplet.
  // Need to find a triplet that is higher than deck value.
  // Given that, need to find another pair.
  return true;
}

bool findTurnOnStraight(DeckState deck, Map<Card, int> cards) {
  return true;
}
