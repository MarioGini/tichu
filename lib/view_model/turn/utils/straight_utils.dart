import 'package:tichu/view_model/turn/tichu_data.dart';
import 'package:tichu/view_model/turn/utils/card_utils.dart';

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

// Returns all possible straights in the list with the desired length. The
// phoenix is not used to create straights by adding at the lower end. Straight
// bombs are not converted to bombs.
List<TichuTurn> getStraights(List<Card> cards, int desiredLength) {
  List<TichuTurn> straights = [];

  // To find straights, we remove duplicates, dragon and dog.
  cards.removeWhere((element) =>
      element.face == CardFace.DRAGON || element.face == CardFace.DOG);
  cards = removeDuplicates(cards);

  // No logic required when less then five cards remain.
  if (cards.length < 5) return straights;

  List<ConnectedCards> connected = findConnectedCards(cards);

  connected.forEach((element) {
    if (element.endIdx - element.beginIdx >= 4) {
      straights.add(TichuTurn(TurnType.STRAIGHT,
          cards.sublist(element.beginIdx, element.endIdx + 1)));
    }
  });

  List<TichuTurn> newAllStraights = [];

  if (cards.any((element) => element.face == CardFace.PHOENIX)) {
    connected.forEach((element) {
      if (element.endIdx - element.beginIdx == 3 &&
          cards[element.beginIdx].value != Card.getValue(CardFace.ACE)) {
        List<Card> phoenixCards =
            cards.sublist(element.beginIdx, element.endIdx + 1);
        phoenixCards.add(Card.phoenix(cards[element.beginIdx].value + 1));
        straights.add(TichuTurn(TurnType.STRAIGHT, phoenixCards));
      }
    });

    for (int i = 1; i < connected.length; ++i) {
      if (cards[connected[i].beginIdx].value + 2 ==
          cards[connected[i - 1].endIdx].value) {
        List<Card> phoenixCards =
            cards.sublist(connected[i - 1].beginIdx, connected[i].endIdx + 1);
        phoenixCards.add(Card.phoenix(cards[connected[i].beginIdx].value + 1));
        straights.add(TichuTurn(TurnType.STRAIGHT, phoenixCards));
      }
    }

    // Pad phoenix to non-phoenix straights at upper end.
    straights.forEach((element) {
      newAllStraights.addAll(paddedPhoenixStraights(element.cards));
    });
  }

  // Add permutations.
  List<TichuTurn> allStraights = [];
  newAllStraights.forEach((element) {
    allStraights.addAll(getStraightPermutations(element.cards));
  });

  allStraights.retainWhere((element) => element.cards.length == desiredLength);

// When having combinations of "pure" straights and phoenix straights, the
// permutation logic will result in duplicated straights which are removed below
// to assure unique elements in the list.
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
