import 'package:tichu/view_model/tichu/card_utils.dart';
import 'package:tichu/view_model/tichu/tichu.dart';
import 'package:tichu/view_model/tichu/tichu_data.dart';

// Simple state machine that computes next wish based on previous wish and
// whether the wish has been satisfied or not.
CardFace computeNextWish(
    CardFace previousWish, TichuTurn currentTurn, CardFace inputWish) {
  if (inputWish != null) {
    return inputWish;
  }
  if (currentTurn.cards.where((element) => element.face == previousWish) !=
      null) {
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
      cards.where((element) => element.face == deck.wish) == null ||
      (turn.cards.where((element) => element.face == deck.wish) != null &&
          validTurn(deck.turn, turn))) {
    return true;
  } else {
    // Player has wish card but it is not selected. Check if it is playable.
    return !canPlayWish(deck, cards);
  }
}

// All functions below assume that cards contain the wish card.
bool canPlayWish(DeckState deck, List<Card> cards) {
  switch (deck.turn.type) {
    case TurnType.SINGLE:
      return canPlayWishOnSingle(deck, cards);
    case TurnType.PAIR:
      return canPlayWishOnPair(deck, cards);
    case TurnType.PAIR_STRAIGHT:
      return findTurnOnPairStraight(deck, cards);
    case TurnType.TRIPLET:
      return canPlayWishOnTriplet(deck, cards);
    case TurnType.FULL_HOUSE:
      return canPlayWishOnFullHouse(deck, cards);
    case TurnType.STRAIGHT:
      return findTurnOnStraight(deck, cards);
    case TurnType.DOG:
      return true;
    case TurnType.BOMB:
      // TODO check whether we have a higher bomb with the wish
      break;
    default:
      // DRAGON is not part of the switch statement because it can only be
      // bombed.
      return false;
  }

  return false;
}

bool canPlayWishOnSingle(DeckState deck, List<Card> cards) {
  return validTurn(
      deck.turn,
      TichuTurn(TurnType.SINGLE,
          [cards.firstWhere((element) => element.face == deck.wish)]));
}

bool canPlayWishOnPair(DeckState deck, List<Card> cards) {
  Card phoenix = Card(CardFace.PHOENIX, Color.SPECIAL);

  if (canPlayCard(deck.wish, deck.turn.value)) {
    if (cards[deck.wish] >= 2 || cards.containsKey(phoenix)) {
      return true;
    } else {
      return false;
    }
  }
  return false;
}

bool findTurnOnPairStraight(DeckState deck, List<Card> cards) {
  return true;
}

bool canPlayWishOnTriplet(DeckState deck, List<Card> cards) {
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

bool canPlayWishOnFullHouse(DeckState deck, List<Card> cards) {
  List<Card> triplets = getTriplets(cards);
  List<Card> pairs = getPairs(cards);

  if (cards.containsKey(Card.PHOENIX)) {
    // When we also have the phoenix, we either need two pairs or a triplet.

    // We have a full house when we have a triplet that is higher as the deck
    // triplet, a phoenix and at least one other card to form the pair.
    if (triplets.length >= 1 &&
        triplets.first.index > deck.turn.value &&
        cards.length >= 3) {
      return true;
    } else {
      // Check whether we can use two pairs and the phoenix.
      return pairs.length >= 2 && pairs.first.index > deck.turn.value;
    }
  } else if (cards[deck.wish] == 2) {
    // The wish is in a pair, we need a triplet.
  } else if (cards[deck.wish] == 3) {
    // The wish is in a triplet, we need a pair.
  } else if (cards[deck.wish] == 4) {
    return true;
  } else {
    // We do not have a phoenix and the wish is not in a multiple set.
    return false;
  }
}

bool findTurnOnStraight(DeckState deck, List<Card> cards) {
  return true;
}
