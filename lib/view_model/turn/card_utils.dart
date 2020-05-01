import 'package:tichu/view_model/turn/tichu_data.dart';

// Returns number of occurrences of the card face in the list.
int occurrences(CardFace face, List<Card> cards) {
  int occurrences = 0;
  cards.forEach((element) {
    if (element.face == face) ++occurrences;
  });

  return occurrences;
}

// Removes cards with duplicate face from list.
List<Card> removeDuplicates(List<Card> cards) {
  List<Card> removedDuplicates = List<Card>.from(cards);

  removedDuplicates.sort(compareCards);
  int k = 0;
  while (removedDuplicates[k + 1] != removedDuplicates.last) {
    if (removedDuplicates[k].value == removedDuplicates[k + 1].value) {
      removedDuplicates.removeAt(k + 1);
    }
    ++k;
  }

  return removedDuplicates;
}

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
  cards.removeWhere((element) {
    bool tooMany;
    tooMany = occurrenceCount[element.face] > 2;
    if (tooMany) {
      --occurrenceCount[element.face];
    }
    return tooMany;
  });

  if (cards.any((element) => element.face == CardFace.PHOENIX)) {
  } else {
    List<Card> pairedCards = List<Card>.from(cards);
    pairedCards.removeWhere((element) => occurrenceCount[element.face] < 2);
    int i = 0;
    int j = 2;
    while (j < pairedCards.length - 2) {
      if (pairedCards[j].value + 1 != pairedCards[j - 2].value) {
        i = j;
        j += 2;
      }
    }
  }

  return pairStraights;
}

// Returns all possible straights in the list. Straight bombs are not converted
// to bombs.
List<TichuTurn> getStraights(List<Card> cards, int desiredLength) {
  List<TichuTurn> straights = [];

  // To find straights, we remove duplicates, dragon and dog.
  cards.removeWhere((element) =>
      element.face == CardFace.DRAGON || element.face == CardFace.DOG);
  cards = removeDuplicates(cards);

  // No logic required when less then five cards remain.
  if (cards.length < 5) return straights;

  if (cards.any((element) => element.face == CardFace.PHOENIX)) {
    // Annoying case, find straight including phoenix.
    // TODO phoenix will require the desired length.
  } else {
    // i is index of straight beginning, j is index of straight ending.
    int i = 0;
    int j = 1;
    while (j < cards.length) {
      if (cards[j].value + 1 != cards[j - 1].value) {
        if (j - i >= 4) {
          straights.add(TichuTurn(TurnType.STRAIGHT, cards.sublist(i, j)));
        }
        i = j;
      }
      ++j;
    }
    // Add straight that includes end card.
    if (cards.length - i >= 5) {
      straights.add(TichuTurn(TurnType.STRAIGHT, cards.sublist(i)));
    }
  }

  List<TichuTurn> allStraights = [];
  straights.forEach((element) {
    allStraights.addAll(getStraightPermutations(element.cards));
  });

  allStraights.removeWhere((element) => element.cards.length != desiredLength);

  return allStraights;
}

// The input must be a valid straight.
List<TichuTurn> getStraightPermutations(List<Card> cards) {
  List<TichuTurn> straightPermutations = [TichuTurn(TurnType.STRAIGHT, cards)];

  int currentPermutationLength = cards.length - 1;

  while (currentPermutationLength >= 5) {
    for (int i = 0; i + currentPermutationLength <= cards.length; ++i) {
      List<Card> subSet = cards.sublist(i, i + currentPermutationLength);
      straightPermutations.add(TichuTurn(TurnType.STRAIGHT, subSet));
    }
    --currentPermutationLength;
  }
  return straightPermutations;
}

// Returns true when all cards in the list have the same color.
bool uniformColor(List<Card> cards) {
  bool uniformColor = true;
  int i = 0;
  while (i <= cards.length - 2) {
    if (cards[i].color != cards[i + 1].color) {
      uniformColor = false;
      break;
    }
    ++i;
  }

  return uniformColor;
}

// Returns true when the cards form a valid straight.
bool isStraight(List<Card> cards) {
  bool isStraight = true;

  // Straights cannot contain dragon or dog, and must consist of at least five
  // cards.
  if (cards.any((element) =>
          element.face == CardFace.DRAGON || element.face == CardFace.DOG) ||
      cards.length < 5) isStraight = false;

  if (isStraight) {
    cards.sort(compareCards);
    int i = 0;

    while (i <= cards.length - 2) {
      if (cards[i].value != cards[i + 1].value + 1) {
        isStraight = false;
        break;
      }
      ++i;
    }
  }

  return isStraight;
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

// Returns true when cards form a valid full house.
bool isFullHouse(List<Card> cards) {
  cards.sort(compareCards);

// When a full house is sorted, the first two and the last two cards are equal.
// The third card can be equal to either the first or second pair.
  return cards.length == 5 &&
      cards[0].value == cards[1].value &&
      cards[3].value == cards[4].value &&
      (cards[2].value == cards[0].value || cards[2].value == cards[4].value);
}
