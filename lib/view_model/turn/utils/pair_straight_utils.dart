import '../tichu_data.dart';
import 'card_utils.dart';

List<TichuTurn> getPairStraights(List<Card> cards, int desiredLength) {
  var pairStraights = <TichuTurn>[];

  cards.removeWhere((element) =>
      element.face == CardFace.dragon || element.face == CardFace.dog);

  if (cards.length < 4 || desiredLength % 2 != 0) return pairStraights;

  cards.sort(compareCards);

  // Remove cards that are present more than twice since they are irrelevant for
  // pair straights.
  var occurrenceCount = getOccurrenceCount(cards);
  cards.removeWhere((element) {
    bool tooMany;
    tooMany = occurrenceCount[element.face] > 2;
    if (tooMany) {
      --occurrenceCount[element.face];
    }
    return tooMany;
  });

  // Create list of all paired cards.
  var pairCards =
      cards.where((element) => occurrenceCount[element.face] == 2).toList();

  // Look for consecutive pairs. findConnectedCards expects a unique list as
  // input. The output is mapped to the indices of the paired list.
  var pairIndices = findConnectedCards(pairCards
          .where((element) => pairCards.indexOf(element) % 2 == 0)
          .toList())
      .map((e) => ConnectedCards(2 * e.beginIdx, 2 * e.endIdx))
      .toList();

  // Add connected pairs as tichu turns.
  for (var seq in pairIndices) {
    if (seq.endIdx - seq.beginIdx >= 2) {
      pairStraights.add(TichuTurn(TurnType.pairStraight,
          pairCards.sublist(seq.beginIdx, seq.endIdx + 2)));
    }
  }

  if (cards.any((element) => element.face == CardFace.phoenix)) {
    // Check for pair straight fusions.
    for (var i = 0; i < pairIndices.length - 1; ++i) {
      var gapValue = pairCards[pairIndices[i].endIdx].value - 1.0;
      if (gapValue == pairCards[pairIndices[i + 1].beginIdx].value + 1.0 &&
          cards.where((element) => element.value == gapValue).isNotEmpty) {
        pairStraights.add(addPhoenixPadding(cards, pairCards,
            pairIndices[i].beginIdx, pairIndices[i + 1].endIdx, gapValue));
      }
    }
    for (var i = 0; i < pairIndices.length; ++i) {
      // Add upper padding when possible
      var desValue = pairCards[pairIndices[i].beginIdx].value + 1.0;
      if (cards.where((element) => element.value == desValue).isNotEmpty) {
        pairStraights.add(addPhoenixPadding(cards, pairCards,
            pairIndices[i].beginIdx, pairIndices[i].endIdx, desValue));
      }
      // Add lower padding when possible
      var desLowerValue = pairCards[pairIndices[i].endIdx].value - 1.0;
      if (cards.where((element) => element.value == desLowerValue).isNotEmpty) {
        pairStraights.add(addPhoenixPadding(cards, pairCards,
            pairIndices[i].beginIdx, pairIndices[i].endIdx, desLowerValue));
      }
    }
  }

  // Add permutations and filter to desired length.
  var allPairStraights = <TichuTurn>[];
  for (var pairStraight in pairStraights) {
    allPairStraights.addAll(getPairStraightPermutations(pairStraight.cards));
  }
  allPairStraights
      .retainWhere((element) => element.cards.length == desiredLength);

  // Remove duplicate elements which come from permutation logic when both
  // standard and phoenix straights are possible.
  var values = <double>{};
  allPairStraights =
      allPairStraights.where((element) => values.add(element.value)).toList();

  return allPairStraights;
}

TichuTurn addPhoenixPadding(List<Card> cards, List<Card> pairCards,
    int beginIdx, int endIdx, double desiredValue) {
  var phoenix = Card.phoenix(desiredValue);
  var phoenixCards = <Card>[
    phoenix,
    cards.where((element) => element.value == desiredValue).single
  ];
  phoenixCards.addAll(pairCards.sublist(beginIdx, endIdx + 2));

  return TichuTurn(TurnType.pairStraight, phoenixCards);
}

// Adds all permutations of shorter straights that are present in longer
// straights.
List<TichuTurn> getPairStraightPermutations(List<Card> cards) {
  assert(isPairStraight(cards));
  var pairStraightPermutations = <TichuTurn>[
    TichuTurn(TurnType.pairStraight, cards)
  ];
  var currentPermutationLength = cards.length - 2;

  while (currentPermutationLength >= 4) {
    for (var i = 0; i + currentPermutationLength <= cards.length; i += 2) {
      var subSet = cards.sublist(i, i + currentPermutationLength);
      pairStraightPermutations.add(TichuTurn(TurnType.pairStraight, subSet));
    }
    currentPermutationLength -= 2;
  }

  return pairStraightPermutations;
}

// Return true when cards form a valid pair straight.
bool isPairStraight(List<Card> cards) {
  var isPairStraight = true;

// Pair straights cannot contain dragon or dog, and must consist of an even
// number of cards that is at least four.
  if (cards.any((element) =>
          element.face == CardFace.dragon || element.face == CardFace.dog) ||
      cards.length < 4 ||
      cards.length % 2 != 0) isPairStraight = false;

  if (isPairStraight) {
    cards.sort(compareCards);
    var i = 0;

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
