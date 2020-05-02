import 'package:tichu/view_model/turn/tichu_data.dart';

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

class ConnectedCards {
  int beginIdx;
  int endIdx;

  ConnectedCards(this.beginIdx, this.endIdx);
}

void findConnectedCards(List<Card> cards) {
  cards.sort(compareCards);
  List<ConnectedCards> connected = [];
  int beginIdx = 0;
  int endIdx = 0;

  for (int i = 1; i < cards.length; ++i) {
    if (cards[i].value + 1 == cards[i - 1].value) {
      ++endIdx;
    } else {
      connected.add(ConnectedCards(beginIdx, endIdx));
      beginIdx = ++endIdx;
    }
  }

  if (endIdx == cards.length) {
    connected.add(ConnectedCards(beginIdx, endIdx - 1));
  }
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
    // Find straight including phoenix.
    int i = 0;
    int j = 1;
    bool phoenixUsed = false;
    while (j < cards.length) {
      if (cards[j].value + 1 != cards[j - 1].value) {
        if (!phoenixUsed) {
          phoenixUsed = true;
          Card phoenix = Card.phoenix(cards[j - 1].value - 1);
          cards.insert(j, phoenix);
        } else {
          if (j - i >= 5) {
            straights.add(TichuTurn(TurnType.STRAIGHT, cards.sublist(i, j)));
          }
          phoenixUsed = false;
          cards.removeWhere((element) =>
              element.face == CardFace.PHOENIX && element.value != -1.0);
          i = j;
        }
      }
      ++j;
    }
    // We don't need to handle the end card case because phoenix card with value
    // -1 is there.

  } else {
    // i is index of straight beginning, j is index of straight ending.
    int i = 0;
    int j = 1;
    while (j < cards.length) {
      if (cards[j].value + 1 != cards[j - 1].value) {
        if (j - i >= 5) {
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

  // Remove straights that have phoenix at the end, unless they have length 5.

  // Pad phoenix to non-phoenix straights at upper end.
  List<TichuTurn> newAllStraights = [];
  if (cards.any((element) => element.face == CardFace.PHOENIX)) {
    straights.forEach((element) {
      newAllStraights.addAll(paddedPhoenixStraights(element.cards));
    });
  }

  List<TichuTurn> allStraights = [];
  newAllStraights.forEach((element) {
    allStraights.addAll(getStraightPermutations(element.cards));
  });

  allStraights.retainWhere((element) => element.cards.length == desiredLength);

  Set<double> values = {};
  allStraights =
      allStraights.where((element) => values.add(element.value)).toList();

  return allStraights;
}

// The input must be a valid straight.
List<TichuTurn> getStraightPermutations(List<Card> cards) {
  assert(isStraight(cards));
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

List<TichuTurn> paddedPhoenixStraights(List<Card> cards) {
  assert(isStraight(cards));
  List<TichuTurn> turns = [TichuTurn(TurnType.STRAIGHT, cards)];

  // When phoenix is already contained, we cannot apply padding.
  if (cards.any((card) => card.face == CardFace.PHOENIX)) return turns;

  cards.sort(compareCards);

  // It only makes sense to pad the phoenix on top of straight.
  if (cards.first.value < Card.getValue(CardFace.ACE)) {
    List<Card> upperPadding = List<Card>.from(cards);
    upperPadding.insert(0, Card.phoenix(cards.first.value + 1));
    turns.add(TichuTurn(TurnType.STRAIGHT, upperPadding));
  }
  return turns;
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
