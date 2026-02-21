import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/card_utils.dart';

List<TichuTurn> getPairStraights(
  final List<Card> cards,
  final int desiredLength,
) {
  final pairStraights = <TichuTurn>[];

  cards.removeWhere(
    (final element) =>
        element.face == CardFace.dragon || element.face == CardFace.dog,
  );

  if (cards.length < 4 || desiredLength % 2 != 0) return pairStraights;

  cards.sort(compareCards);

  // Remove cards that are present more than twice since they are irrelevant for
  // pair straights.
  final occurrenceCount = getOccurrenceCount(cards);
  cards.removeWhere((final card) {
    final tooMany = occurrenceCount[card.face]! > 2;
    if (tooMany) {
      occurrenceCount[card.face] = occurrenceCount[card.face]! - 1;
    }
    return tooMany;
  });

  // Create list of all paired cards.
  final pairCards = cards
      .where((final element) => occurrenceCount[element.face] == 2)
      .toList();

  // Look for consecutive pairs. findConnectedCards expects a unique list as
  // input. The output is mapped to the indices of the paired list.
  final pairIndices = findConnectedCards(
    pairCards
        .where((final element) => pairCards.indexOf(element).isEven)
        .toList(),
  ).map((final e) => ConnectedCards(2 * e.beginIdx, 2 * e.endIdx)).toList();

  // Add connected pairs as tichu turns.
  for (final seq in pairIndices) {
    if (seq.endIdx - seq.beginIdx >= 2) {
      pairStraights.add(
        TichuTurn(
          TurnType.pairStraight,
          pairCards.sublist(seq.beginIdx, seq.endIdx + 2),
        ),
      );
    }
  }

  if (cards.any((final element) => element.face == CardFace.phoenix)) {
    // Check for pair straight fusions.
    for (var i = 0; i < pairIndices.length - 1; ++i) {
      final gapValue = pairCards[pairIndices[i].endIdx].value - 1.0;
      if (gapValue == pairCards[pairIndices[i + 1].beginIdx].value + 1.0 &&
          cards
              .where((final element) => element.value == gapValue)
              .isNotEmpty) {
        pairStraights.add(
          addPhoenixPadding(
            cards,
            pairCards,
            pairIndices[i].beginIdx,
            pairIndices[i + 1].endIdx,
            gapValue,
          ),
        );
      }
    }
    for (var i = 0; i < pairIndices.length; ++i) {
      // Add upper padding when possible
      final desValue = pairCards[pairIndices[i].beginIdx].value + 1.0;
      if (cards
          .where((final element) => element.value == desValue)
          .isNotEmpty) {
        pairStraights.add(
          addPhoenixPadding(
            cards,
            pairCards,
            pairIndices[i].beginIdx,
            pairIndices[i].endIdx,
            desValue,
          ),
        );
      }
      // Add lower padding when possible
      final desLowerValue = pairCards[pairIndices[i].endIdx].value - 1.0;
      if (cards
          .where((final element) => element.value == desLowerValue)
          .isNotEmpty) {
        pairStraights.add(
          addPhoenixPadding(
            cards,
            pairCards,
            pairIndices[i].beginIdx,
            pairIndices[i].endIdx,
            desLowerValue,
          ),
        );
      }
    }
  }

  // Add permutations and filter to desired length.
  final allPairStraights = <TichuTurn>[];
  for (final pairStraight in pairStraights) {
    allPairStraights.addAll(getPairStraightPermutations(pairStraight.cards));
  }
  allPairStraights.retainWhere(
    (final element) => element.cards.length == desiredLength,
  );

  // Remove duplicate elements which come from permutation logic when both
  // standard and phoenix straights are possible.
  final values = <double>{};
  return allPairStraights
      .where((final element) => values.add(element.value))
      .toList();
}

TichuTurn addPhoenixPadding(
  final List<Card> cards,
  final List<Card> pairCards,
  final int beginIdx,
  final int endIdx,
  final double desiredValue,
) {
  final phoenix = Card.phoenix(desiredValue);
  final phoenixCards = <Card>[
    phoenix,
    cards.where((final element) => element.value == desiredValue).single,
  ];
  phoenixCards.addAll(pairCards.sublist(beginIdx, endIdx + 2));

  return TichuTurn(TurnType.pairStraight, phoenixCards);
}

// Adds all permutations of shorter straights that are present in longer
// straights.
List<TichuTurn> getPairStraightPermutations(final List<Card> cards) {
  assert(isPairStraight(cards), 'cards must form a valid pair straight');
  final pairStraightPermutations = <TichuTurn>[
    TichuTurn(TurnType.pairStraight, cards),
  ];
  var currentPermutationLength = cards.length - 2;

  while (currentPermutationLength >= 4) {
    for (var i = 0; i + currentPermutationLength <= cards.length; i += 2) {
      final subSet = cards.sublist(i, i + currentPermutationLength);
      pairStraightPermutations.add(TichuTurn(TurnType.pairStraight, subSet));
    }
    currentPermutationLength -= 2;
  }

  return pairStraightPermutations;
}

// Return true when cards form a valid pair straight.
bool isPairStraight(final List<Card> cards) {
  var isPairStraight = true;

  // Pair straights cannot contain dragon or dog, and must consist of an even
  // number of cards that is at least four.
  if (cards.any(
        (final element) =>
            element.face == CardFace.dragon || element.face == CardFace.dog,
      ) ||
      cards.length < 4 ||
      cards.length % 2 != 0) {
    isPairStraight = false;
  }

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
