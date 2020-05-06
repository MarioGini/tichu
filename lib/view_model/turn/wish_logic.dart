import 'package:tichu/view_model/turn/utils/bomb_utils.dart';
import 'package:tichu/view_model/turn/utils/card_utils.dart';
import 'package:tichu/view_model/turn/utils/straight_utils.dart';
import 'package:tichu/view_model/turn/utils/pair_straight_utils.dart';
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

// Returns true when wish could be played but is not selected.
bool mahJong(DeckState deck, TichuTurn turn, List<Card> cards) {
  // We automatically obey in three cases:
  // - There is no wish.
  // - We cannot fulfill the wish.
  // - We fulfill the wish.
  if (deck.wish == null ||
      cards.every((element) => element.face != deck.wish) ||
      turn.cards.any((element) => element.face == deck.wish)) {
    return false;
  } else {
    // Player has wish card but it is not selected. Check if it is playable.
    return canPlayWish(deck, cards);
  }
}

// All functions below assume that cards contain the wish card.
bool canPlayWish(DeckState deck, List<Card> cards) {
  // Check whether we have a bomb with the wish and the bomb is playable.
  if (haveValidWishBomb(deck, cards)) {
    return true;
  }

  switch (deck.turn.type) {
    case TurnType.SINGLE:
      return canPlayWishOnSingle(deck, cards);
    case TurnType.PAIR:
      return canPlayWishOnPair(deck, cards);
    case TurnType.PAIR_STRAIGHT:
      return canPlayWishOnPairStraight(deck, cards);
    case TurnType.TRIPLET:
      return canPlayWishOnTriplet(deck, cards);
    case TurnType.FULL_HOUSE:
    //return canPlayWishOnFullHouse(deck, cards);
    case TurnType.STRAIGHT:
      return canPlayWishOnStraight(deck, cards);
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
bool haveValidWishBomb(DeckState deck, List<Card> cards) {
  // Get a list of bombs that contain at least one wish card.
  List<TichuTurn> wishBombs = getBombs(cards)
      .where((bomb) => bomb.cards.any((card) => card.face == deck.wish))
      .toList();
  wishBombs.sort(compareTurns);

  // We have a playable wish bomb when no bomb is on the deck or when we have a
  // higher bomb.
  return wishBombs.length != 0 &&
      (deck.turn.type != TurnType.BOMB ||
          wishBombs.first.value > deck.turn.value);
}

bool canPlayWishOnSingle(DeckState deck, List<Card> cards) {
  return TichuTurn(TurnType.SINGLE,
          [cards.firstWhere((element) => element.face == deck.wish)]).value >
      deck.turn.value;
}

bool canPlayWishOnPair(DeckState deck, List<Card> cards) {
  // Can play wish when we have at least two of them or one and the phoenix.
  return Card.getValue(deck.wish) > deck.turn.value &&
      (occurrences(deck.wish, cards) >= 2 ||
          cards.any((element) => element.face == CardFace.PHOENIX));
}

bool canPlayWishOnPairStraight(DeckState deck, List<Card> cards) {
  List<TichuTurn> possibleTurns =
      getPairStraights(cards, deck.turn.cards.length);

  possibleTurns.retainWhere(
      (element) => element.cards.any((element) => element.face == deck.wish));

  return possibleTurns.any((element) => element.value > deck.turn.value);
}

bool canPlayWishOnTriplet(DeckState deck, List<Card> cards) {
  return Card(deck.wish, null).value > deck.turn.value &&
          occurrences(deck.wish, cards) == 3 ||
      (cards.any((element) => element.face == CardFace.PHOENIX) &&
          occurrences(deck.wish, cards) == 2);
}

bool canPlayWishOnStraight(DeckState deck, List<Card> cards) {
  List<TichuTurn> possibleTurns = getStraights(cards, deck.turn.cards.length);

  possibleTurns.retainWhere(
      (element) => element.cards.any((element) => element.face == deck.wish));

  return possibleTurns.any((element) => element.value > deck.turn.value);
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
