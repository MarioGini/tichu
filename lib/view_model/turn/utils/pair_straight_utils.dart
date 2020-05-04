import 'package:tichu/view_model/turn/tichu_data.dart';
import 'package:tichu/view_model/turn/utils/card_utils.dart';

List<TichuTurn> getPairStraights(List<Card> cards, int desiredLength) {
  List<TichuTurn> pairStraights = [];

  cards.removeWhere((element) =>
      element.face == CardFace.DRAGON || element.face == CardFace.DOG);

  if (cards.length < 4 || desiredLength % 2 != 0) return pairStraights;

  cards.sort(compareCards);

  Map<CardFace, int> occurrenceCount = {};
  cards.forEach((element) {
    if (occurrenceCount.containsKey(element.face)) {
      ++occurrenceCount[element.face];
    } else {
      occurrenceCount[element.face] = 1;
    }
  });
  // Remove cards that are present more than twice.
  cards.removeWhere((element) {
    bool tooMany;
    tooMany = occurrenceCount[element.face] > 2;
    if (tooMany) {
      --occurrenceCount[element.face];
    }
    return tooMany;
  });

  // Keep only one card per pair and then look for connectedness.
  List<Card> pairCards =
      cards.where((element) => occurrenceCount[element.face] == 2).toList();

  List<Card> uniqueCards = [];
  pairCards.forEach((element) {
    if (pairCards.indexOf(element) % 2 == 0) {
      uniqueCards.add(element);
    }
  });

  List<ConnectedCards> connected = findConnectedCards(uniqueCards);

  // Iterate through connects, add cards to turns from paired list
  // accordingly.
  connected.forEach((element) {
    if (element.endIdx - element.beginIdx >= 1) {
      pairStraights.add(TichuTurn(TurnType.PAIR_STRAIGHT,
          pairCards.sublist(2 * element.beginIdx, 2 * (element.endIdx + 1))));
    }
  });

  if (cards.any((element) => element.face == CardFace.PHOENIX)) {
    // Check for pair straight fusions.
    for (int i = 0; i < connected.length - 1; ++i) {
      double gapValue = uniqueCards[connected[i].endIdx].value - 1.0;
      if (gapValue == uniqueCards[connected[i + 1].beginIdx].value + 1.0) {
        Card phoenix = Card.phoenix(gapValue);
        List<Card> phoenixCards = [
          phoenix,
          cards.where((element) => element.value == gapValue).single
        ];
        phoenixCards.addAll(pairCards.sublist(
            2 * connected[i].beginIdx, 2 * (connected[i + 1].endIdx + 1)));
        pairStraights.add(TichuTurn(TurnType.PAIR_STRAIGHT, phoenixCards));
      }
    }
    for (int i = 0; i < connected.length; ++i) {
      // Add upper padding when possible
      double desValue = uniqueCards[connected[i].beginIdx].value + 1.0;
      if (cards.where((element) => element.value == desValue).length != 0) {
        Card phoenix = Card.phoenix(desValue);
        List<Card> phoenixCards = [
          phoenix,
          cards.where((element) => element.value == desValue).single
        ];
        phoenixCards.addAll(pairCards.sublist(
            2 * connected[i].beginIdx, 2 * (connected[i].endIdx + 1)));

        pairStraights.add(TichuTurn(TurnType.PAIR_STRAIGHT, phoenixCards));
      }
      // Add lower padding when possible
      double desLowerValue = uniqueCards[connected[i].endIdx].value - 1.0;
      if (cards.where((element) => element.value == desLowerValue).length !=
          0) {
        Card phoenix = Card.phoenix(desLowerValue);
        List<Card> phoenixCards = [
          phoenix,
          cards.where((element) => element.value == desLowerValue).single
        ];
        phoenixCards.addAll(pairCards.sublist(
            2 * connected[i].beginIdx, 2 * (connected[i].endIdx + 1)));

        pairStraights.add(TichuTurn(TurnType.PAIR_STRAIGHT, phoenixCards));
      }
    }
  }

  // Add permutations.
  List<TichuTurn> allPairStraights = [];
  pairStraights.forEach((element) {
    allPairStraights.addAll(getPairStraightPermutations(element.cards));
  });

  // Filter the desired lengths.
  allPairStraights
      .retainWhere((element) => element.cards.length == desiredLength);

  // Remove duplicate elements.
  Set<double> values = {};
  allPairStraights =
      allPairStraights.where((element) => values.add(element.value)).toList();

  return allPairStraights;
}

// Input must be a valid pair straight.
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
