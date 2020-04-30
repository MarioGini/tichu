import 'package:tichu/view_model/turn/card_utils.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';

// Simple state machine that computes next wish based on previous wish and
// whether the wish has been satisfied or not.
CardFace computeNextWish(
    CardFace previousWish, TichuTurn currentTurn, CardFace inputWish) {
  if (inputWish != null) {
    return inputWish;
  }
  if (currentTurn.cards.any((element) => element.face == previousWish)) {
    return null;
  } else {
    return previousWish;
  }
}

/// Returns true when the wish rules are being followed, false else.
bool obeyMahJong(DeckState deck, TichuTurn turn, List<Card> cards) {
  // We automatically obey in three cases:
  // - There is no wish.
  // - We cannot fulfill the wish.
  // - We fulfill the wish.
  if (deck.wish == null ||
      cards.every((element) => element.face != deck.wish) ||
      turn.cards.any((element) => element.face == deck.wish)) {
    return true;
  } else {
    // Player has wish card but it is not selected. Check if it is playable.
    return !canPlayWish(deck, cards);
  }
}

// All functions below assume that cards contain the wish card.
bool canPlayWish(DeckState deck, List<Card> cards) {
  // Check whether we have a bomb with the wish and the bomb is playable.
  if (playableBomb(deck, cards)) {
    return true;
  }

  switch (deck.turn.type) {
    case TurnType.SINGLE:
      return canPlayWishOnSingle(deck, cards);
    case TurnType.PAIR:
      return canPlayWishOnPair(deck, cards);
    case TurnType.PAIR_STRAIGHT:
    // return findTurnOnPairStraight(deck, cards);
    case TurnType.TRIPLET:
      return canPlayWishOnTriplet(deck, cards);
    case TurnType.FULL_HOUSE:
    //return canPlayWishOnFullHouse(deck, cards);
    case TurnType.STRAIGHT:
    //return findTurnOnStraight(deck, cards);
    case TurnType.DOG:
      return true;
    case TurnType.DRAGON:
      // The dragon cannot be beaten, bomb case is handled before that.
      return false;
    default:
      return false;
  }
}

// Returns true when cards contain playable bomb including the wish card.
bool playableBomb(DeckState deck, List<Card> cards) {
  bool havePlayableBomb = false;
  if (occurrences(deck.wish, cards) == 4) {
    if (deck.turn.type != TurnType.BOMB) {
      havePlayableBomb = true;
    } else {
      havePlayableBomb = Card(deck.wish, null).value > deck.turn.value;
    }
  } else {
    // Check for a straight bomb.
  }

  return havePlayableBomb;
}

bool canPlayWishOnSingle(DeckState deck, List<Card> cards) {
  return TichuTurn(TurnType.SINGLE,
          [cards.firstWhere((element) => element.face == deck.wish)]).value >
      deck.turn.value;
}

bool canPlayWishOnPair(DeckState deck, List<Card> cards) {
  // Can play wish when we have at least two of them or one and the phoenix.
  return Card(deck.wish, null).value > deck.turn.value &&
      (cards.any((element) => element.face == CardFace.PHOENIX) ||
          occurrences(deck.wish, cards) >= 2);
}

bool canPlayWishOnTriplet(DeckState deck, List<Card> cards) {
  return Card(deck.wish, null).value > deck.turn.value &&
          occurrences(deck.wish, cards) >= 3 ||
      (cards.any((element) => element.face == CardFace.PHOENIX) &&
          occurrences(deck.wish, cards) >= 2);
}

bool canPlayWishOnFullHouse(DeckState deck, List<Card> cards) {
  if (cards.any((element) => element.face == CardFace.PHOENIX)) {
    // When we also have the phoenix, we either need two pairs or a triplet.
    int i = 2;
    // We have a full house when we have a triplet that is higher as the deck
    // triplet, a phoenix and at least one other card to form the pair.
    if (i == 3) {
      return true;
    } else {
      // Check whether we can use two pairs and the phoenix.
    }
  } else if (occurrences(deck.wish, cards) == 2) {
    // The wish is in a pair, we need a triplet.
  } else if (occurrences(deck.wish, cards) == 3) {
    // The wish is in a triplet, we need a pair.
  } else {
    // We do not have a phoenix and the wish is not in a multiple set.
    return false;
  }

  return false;
}
