import 'package:tichu/view_model/tichu.dart';
import 'package:tichu/view_model/tichu_data.dart';

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
    List<TichuTurn> possibleTurns = findPossibleTurns(deck.turn, cards);

    // If any possible turn contains the wish card, return false.
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

List<TichuTurn> findPossibleTurns(TichuTurn turn, List<Card> cards) {
  List<TichuTurn> returnValue;
  switch (turn.type) {
    case TurnType.SINGLE:
      returnValue = findTurnsOnSingle(turn, cards);
      break;
    case TurnType.PAIR:
      returnValue = findTurnOnPair(turn, cards);
      break;
    case TurnType.TRIPLET:
      returnValue = findTurnOnTriplet(turn, cards);
      break;
    case TurnType.PAIR_STRAIGHT:
      returnValue = findTurnOnPairStraight(turn, cards);
      break;
    case TurnType.FULL_HOUSE:
      returnValue = findTurnOnFullHouse(turn, cards);
      break;
    case TurnType.STRAIGHT_OF_5:
      returnValue = findTurnOnStraight(turn, cards);
      break;

    default:
      break;
  }

  return returnValue;
}

List<TichuTurn> findTurnsOnSingle(TichuTurn turn, List<Card> cards) {}
List<TichuTurn> findTurnOnPair(TichuTurn turn, List<Card> cards) {}
List<TichuTurn> findTurnOnPairStraight(TichuTurn turn, List<Card> cards) {}
List<TichuTurn> findTurnOnTriplet(TichuTurn turn, List<Card> cards) {}
List<TichuTurn> findTurnOnFullHouse(TichuTurn turn, List<Card> cards) {}
List<TichuTurn> findTurnOnStraight(TichuTurn turn, List<Card> cards) {}
