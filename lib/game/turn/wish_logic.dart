import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/bomb_utils.dart';
import 'package:tichu/game/turn/utils/card_utils.dart';
import 'package:tichu/game/turn/utils/full_house_utils.dart';
import 'package:tichu/game/turn/utils/pair_straight_utils.dart';
import 'package:tichu/game/turn/utils/straight_utils.dart';

// Simple state machine that computes next wish based on previous wish and
// whether the wish has been satisfied or not.
CardFace computeNextWish(
  final CardFace previousWish,
  final TichuTurn currentTurn,
  final CardFace inputWish,
) {
  if (inputWish != CardFace.none) {
    return inputWish;
  }
  if (currentTurn.cards.any((final element) => element.face == previousWish)) {
    return CardFace.none;
  } else {
    return previousWish;
  }
}

// Returns true when wish could be played but is not selected.
bool mahJong(
  final DeckState deck,
  final TichuTurn turn,
  final List<Card> cards,
) {
  // We automatically obey in three cases:
  // - There is no wish.
  // - We cannot fulfill the wish.
  // - We fulfill the wish.
  if (deck.wish == CardFace.none ||
      cards.every((final element) => element.face != deck.wish) ||
      turn.cards.any((final element) => element.face == deck.wish)) {
    return false;
  } else {
    // Player has wish card but it is not selected. Check if it is playable.
    return canPlayWish(deck, cards);
  }
}

// All functions below assume that cards contain the wish card.
bool canPlayWish(final DeckState deck, final List<Card> cards) {
  // Check whether we have a bomb with the wish and the bomb is playable.
  if (haveValidWishBomb(deck, cards)) {
    return true;
  }

  switch (deck.turn.type) {
    case TurnType.none:
      return true;
    case TurnType.empty:
      return true;
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
    case TurnType.bomb:
      return false;
  }
}

// Returns true when cards contain playable bomb including the wish card.
bool haveValidWishBomb(final DeckState deck, final List<Card> cards) {
  // Get a list of bombs that contain at least one wish card.
  final wishBombs = getBombs(cards)
      .where(
        (final bomb) => bomb.cards.any((final card) => card.face == deck.wish),
      )
      .toList();
  wishBombs.sort(compareTurns);

  // We have a playable wish bomb when no bomb is on the deck or when we have a
  // higher bomb.
  return wishBombs.isNotEmpty &&
      (deck.turn.type != TurnType.bomb ||
          wishBombs.first.value > deck.turn.value);
}

bool canPlayWishOnSingle(final DeckState deck, final List<Card> cards) =>
    TichuTurn(TurnType.single, [
      cards.firstWhere((final element) => element.face == deck.wish),
    ]).value >
    deck.turn.value;

bool canPlayWishOnPair(final DeckState deck, final List<Card> cards) =>
    // Can play wish when we have at least two of them or one and the phoenix.
    Card.getValue(deck.wish) > deck.turn.value &&
    (occurrences(deck.wish, cards) >= 2 ||
        cards.any((final element) => element.face == CardFace.phoenix));

bool canPlayWishOnPairStraight(final DeckState deck, final List<Card> cards) {
  final possibleTurns = getPairStraights(cards, deck.turn.cards.length);

  possibleTurns.retainWhere(
    (final element) =>
        element.cards.any((final element) => element.face == deck.wish),
  );

  return possibleTurns.any((final element) => element.value > deck.turn.value);
}

bool canPlayWishOnTriplet(final DeckState deck, final List<Card> cards) =>
    Card(deck.wish, CardColor.black).value > deck.turn.value &&
    (occurrences(deck.wish, cards) == 3 ||
        (cards.any((final element) => element.face == CardFace.phoenix) &&
            occurrences(deck.wish, cards) == 2));

bool canPlayWishOnStraight(final DeckState deck, final List<Card> cards) {
  final possibleTurns = getStraights(cards, deck.turn.cards.length);

  possibleTurns.retainWhere(
    (final element) =>
        element.cards.any((final element) => element.face == deck.wish),
  );

  return possibleTurns.any((final element) => element.value > deck.turn.value);
}

/// Whether [face] is a valid wish target (2–A, excluding specials).
bool isWishableFace(final CardFace face) => switch (face) {
  CardFace.two ||
  CardFace.three ||
  CardFace.four ||
  CardFace.five ||
  CardFace.six ||
  CardFace.seven ||
  CardFace.eight ||
  CardFace.nine ||
  CardFace.ten ||
  CardFace.jack ||
  CardFace.queen ||
  CardFace.king ||
  CardFace.ace => true,
  _ => false,
};

/// Returns the default wish face derived from schupf selections.
///
/// The convention is to wish for the face of the card given to
/// Opponent 1 (UI right-side opponent for the human player), as this
/// target is preferred for the default Mahjong wish.
CardFace? defaultWishFaceFromSchupf({
  required final Card? toLeft,
  required final Card? toPartner,
  required final Card? toRight,
}) => toLeft?.face;

bool canPlayWishOnFullHouse(final DeckState deck, final List<Card> cards) {
  final possibleTurns = getFullHouses(cards);

  possibleTurns.retainWhere(
    (final element) =>
        element.cards.any((final element) => element.face == deck.wish),
  );

  return possibleTurns.any((final element) => element.value > deck.turn.value);
}
