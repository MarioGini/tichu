import 'package:tichu/view_model/turn/tichu_data.dart';

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
  // Remove cards that are present more than twice such that the pair straight
  // algorithm works.
  cards.removeWhere((element) {
    bool tooMany;
    tooMany = occurrenceCount[element.face] > 2;
    if (tooMany) {
      --occurrenceCount[element.face];
    }
    return tooMany;
  });

  if (cards.any((element) => element.face == CardFace.PHOENIX)) {
    // Phoenix logic.

  } else {
    // We look for chains of paired cards. The potentially long chains will then
    // be divided in all possible pair straight combinations in a second step
    // below.
    List<Card> pairedCards = List<Card>.from(cards);
    pairedCards.removeWhere((element) => occurrenceCount[element.face] < 2);
    int i = 0;
    int j = 2;
    while (j < pairedCards.length - 1) {
      if (pairedCards[j].value + 1 != pairedCards[j - 2].value) {
        if (j - i > 2) {
          pairStraights.add(
              TichuTurn(TurnType.PAIR_STRAIGHT, pairedCards.sublist(i, j)));
        }
        i = j;
      }
      j += 2;
    }
    // Add pair straights that include end card.
    if (pairedCards.length - i >= 4) {
      pairStraights
          .add(TichuTurn(TurnType.PAIR_STRAIGHT, pairedCards.sublist(i)));
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
