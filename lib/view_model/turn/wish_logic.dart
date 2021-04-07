import 'tichu_data.dart';
import 'utils/bomb_utils.dart';
import 'utils/card_utils.dart';
import 'utils/full_house_utils.dart';
import 'utils/pair_straight_utils.dart';
import 'utils/straight_utils.dart';

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
    case TurnType.single:
      return canPlayWishOnSingle(deck, cards);
    case TurnType.pair:
      return canPlayWishOnPair(deck, cards);
    case TurnType.pairStraight:
      return canPlayWishOnPairStraight(deck, cards);
    case TurnType.triplet:
      return canPlayWishOnTriplet(deck, cards);
    case TurnType.fullHouse:
      return canPlayWishOnFullHouse(deck, cards);
    case TurnType.straight:
      return canPlayWishOnStraight(deck, cards);
    case TurnType.dog:
      return true;
    default:
      return false;
  }
}

// Returns true when cards contain playable bomb including the wish card.
bool haveValidWishBomb(DeckState deck, List<Card> cards) {
  // Get a list of bombs that contain at least one wish card.
  var wishBombs = getBombs(cards)
      .where((bomb) => bomb.cards.any((card) => card.face == deck.wish))
      .toList();
  wishBombs.sort(compareTurns);

  // We have a playable wish bomb when no bomb is on the deck or when we have a
  // higher bomb.
  return wishBombs.isNotEmpty &&
      (deck.turn.type != TurnType.bomb ||
          wishBombs.first.value > deck.turn.value);
}

bool canPlayWishOnSingle(DeckState deck, List<Card> cards) {
  return TichuTurn(TurnType.single,
          [cards.firstWhere((element) => element.face == deck.wish)]).value >
      deck.turn.value;
}

bool canPlayWishOnPair(DeckState deck, List<Card> cards) {
  // Can play wish when we have at least two of them or one and the phoenix.
  return Card.getValue(deck.wish) > deck.turn.value &&
      (occurrences(deck.wish, cards) >= 2 ||
          cards.any((element) => element.face == CardFace.phoenix));
}

bool canPlayWishOnPairStraight(DeckState deck, List<Card> cards) {
  var possibleTurns = getPairStraights(cards, deck.turn.cards.length);

  possibleTurns.retainWhere(
      (element) => element.cards.any((element) => element.face == deck.wish));

  return possibleTurns.any((element) => element.value > deck.turn.value);
}

bool canPlayWishOnTriplet(DeckState deck, List<Card> cards) {
  return Card(deck.wish, null).value > deck.turn.value &&
          occurrences(deck.wish, cards) == 3 ||
      (cards.any((element) => element.face == CardFace.phoenix) &&
          occurrences(deck.wish, cards) == 2);
}

bool canPlayWishOnStraight(DeckState deck, List<Card> cards) {
  var possibleTurns = getStraights(cards, deck.turn.cards.length);

  possibleTurns.retainWhere(
      (element) => element.cards.any((element) => element.face == deck.wish));

  return possibleTurns.any((element) => element.value > deck.turn.value);
}

bool canPlayWishOnFullHouse(DeckState deck, List<Card> cards) {
  var possibleTurns = getFullHouses(cards);

  possibleTurns.retainWhere(
      (element) => element.cards.any((element) => element.face == deck.wish));

  return possibleTurns.any((element) => element.value > deck.turn.value);
}
