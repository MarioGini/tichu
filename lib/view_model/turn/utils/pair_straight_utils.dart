import 'package:tichu/view_model/turn/tichu_data.dart';
import 'package:tichu/view_model/turn/utils/card_utils.dart';

List<TichuTurn> getPairStraights(List<Card> cards, int desiredLength) {
  List<TichuTurn> pairStraights = [];

  cards.removeWhere((element) =>
      element.face == CardFace.DRAGON || element.face == CardFace.DOG);

  if (cards.length < 4 || desiredLength % 2 != 0) return pairStraights;

  cards.sort(compareCards);

  // Remove cards that are present more than twice since they are irrelevant for
  // pair straights.
  Map<CardFace, int> occurrenceCount = getOccurrenceCount(cards);
  cards.removeWhere((element) {
    bool tooMany;
    tooMany = occurrenceCount[element.face] > 2;
    if (tooMany) {
      --occurrenceCount[element.face];
    }
    return tooMany;
  });

  // Create list of all paired cards.
  List<Card> pairCards =
      cards.where((element) => occurrenceCount[element.face] == 2).toList();

  // Look for consecutive pairs. findConnectedCards expects a unique list as
  // input. The output is mapped to the indices of the paired list.
  List<ConnectedCards> pairIndices = findConnectedCards(pairCards
          .where((element) => pairCards.indexOf(element) % 2 == 0)
          .toList())
      .map((e) => ConnectedCards(2 * e.beginIdx, 2 * e.endIdx))
      .toList();

  // Add connected pairs as tichu turns.
  pairIndices.forEach((element) {
    if (element.endIdx - element.beginIdx >= 2) {
      pairStraights.add(TichuTurn(TurnType.PAIR_STRAIGHT,
          pairCards.sublist(element.beginIdx, element.endIdx + 2)));
    }
  });

  if (cards.any((element) => element.face == CardFace.PHOENIX)) {
    // Check for pair straight fusions.
    for (int i = 0; i < pairIndices.length - 1; ++i) {
      double gapValue = pairCards[pairIndices[i].endIdx].value - 1.0;
      if (gapValue == pairCards[pairIndices[i + 1].beginIdx].value + 1.0 &&
          cards.where((element) => element.value == gapValue).length != 0) {
        pairStraights.add(addPhoenixPadding(cards, pairCards,
            pairIndices[i].beginIdx, pairIndices[i + 1].endIdx, gapValue));
      }
    }
    for (int i = 0; i < pairIndices.length; ++i) {
      // Add upper padding when possible
      double desValue = pairCards[pairIndices[i].beginIdx].value + 1.0;
      if (cards.where((element) => element.value == desValue).length != 0) {
        pairStraights.add(addPhoenixPadding(cards, pairCards,
            pairIndices[i].beginIdx, pairIndices[i].endIdx, desValue));
      }
      // Add lower padding when possible
      double desLowerValue = pairCards[pairIndices[i].endIdx].value - 1.0;
      if (cards.where((element) => element.value == desLowerValue).length !=
          0) {
        pairStraights.add(addPhoenixPadding(cards, pairCards,
            pairIndices[i].beginIdx, pairIndices[i].endIdx, desLowerValue));
      }
    }
  }

  // Add permutations and filter to desired length.
  List<TichuTurn> allPairStraights = [];
  pairStraights.forEach((element) {
    allPairStraights.addAll(getPairStraightPermutations(element.cards));
  });
  allPairStraights
      .retainWhere((element) => element.cards.length == desiredLength);

  // Remove duplicate elements which come from permutation logic when both
  // standard and phoenix straights are possible.
  Set<double> values = {};
  allPairStraights =
      allPairStraights.where((element) => values.add(element.value)).toList();

  return allPairStraights;
}

TichuTurn addPhoenixPadding(List<Card> cards, List<Card> pairCards,
    int beginIdx, int endIdx, double desiredValue) {
  Card phoenix = Card.phoenix(desiredValue);
  List<Card> phoenixCards = [
    phoenix,
    cards.where((element) => element.value == desiredValue).single
  ];
  phoenixCards.addAll(pairCards.sublist(beginIdx, endIdx + 2));

  return TichuTurn(TurnType.PAIR_STRAIGHT, phoenixCards);
}

// Adds all permutations of shorter straights that are present in longer
// straights.
List<TichuTurn> getPairStraightPermutations(List<Card> cards) {
  assert(isPairStraight(cards));
  List<TichuTurn> pairStraightPermutations = [
    TichuTurn(TurnType.PAIR_STRAIGHT, cards)
  ];
  int currentPermutationLength = cards.length - 2;

  while (currentPermutationLength >= 4) {
    for (int i = 0; i + currentPermutationLength <= cards.length; i += 2) {
      List<Card> subSet = cards.sublist(i, i + currentPermutationLength);
      pairStraightPermutations.add(TichuTurn(TurnType.PAIR_STRAIGHT, subSet));
    }
    currentPermutationLength -= 2;
  }

  return pairStraightPermutations;
}

// Return true when cards form a valid pair straight.
bool isPairStraight(List<Card> cards) {
  bool isPairStraight = true;

// Pair straights cannot contain dragon or dog, and must consist of an even
// number of cards that is at least four.
  if (cards.any((element) =>
          element.face == CardFace.DRAGON || element.face == CardFace.DOG) ||
      cards.length < 4 ||
      cards.length % 2 != 0) isPairStraight = false;

  if (isPairStraight) {
    cards.sort(compareCards);
    int i = 0;

    while (i <= cards.length - 4) {
      if (cards[i].value != cards[i + 1].value ||
          cards[i].value != cards[i + 2].value + 1 ||
          cards[i].value != cards[i + 3].value + 1) {
        isPairStraight = false;
        break;
      }
      i += 2;
    }
  }

  return isPairStraight;
}
