import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/card_utils.dart';

// Removes cards with duplicate face from list.
List<Card> removeDuplicates(final List<Card> cards) {
  if (cards.isEmpty) return [];

  final removedDuplicates = List<Card>.from(cards);

  removedDuplicates.sort(compareCards);
  var k = 0;
  while (true) {
    if (k == removedDuplicates.length - 1) break;
    if (removedDuplicates[k].value == removedDuplicates[k + 1].value) {
      removedDuplicates.removeAt(k + 1);
    } else {
      ++k;
    }
  }

  return removedDuplicates;
}

// Returns all possible straights in the list with the desired length. The
// phoenix is not used to create straights by adding at the lower end. Straight
// bombs are not converted to bombs.
List<TichuTurn> getStraights(List<Card> cards, final int desiredLength) {
  final straights = <TichuTurn>[];

  // To find straights, we remove duplicates, dragon and dog.
  cards.removeWhere(
    (final element) =>
        element.face == CardFace.dragon || element.face == CardFace.dog,
  );
  final uniqueCards = removeDuplicates(cards);

  // No logic required when less then five cards remain.
  if (uniqueCards.length < 5) return straights;

  // Look for consecutive cards and add segments that have length of at least
  // five.
  final connected = findConnectedCards(uniqueCards);
  for (final sequence in connected) {
    if (sequence.endIdx - sequence.beginIdx >= 4) {
      straights.add(
        TichuTurn(
          TurnType.straight,
          uniqueCards.sublist(sequence.beginIdx, sequence.endIdx + 1),
        ),
      );
    }
  }

  if (uniqueCards.any((final element) => element.face == CardFace.phoenix)) {
    final phoenixStraights = <TichuTurn>[];
    // Phoenix is added to all segments that have length of at least four. When
    // highest card is not an ace, phoenix is added as first card, else as last
    // card.
    for (final sequence in connected) {
      if (sequence.endIdx - sequence.beginIdx >= 3) {
        final phoenixCards = uniqueCards.sublist(
          sequence.beginIdx,
          sequence.endIdx + 1,
        );
        if (uniqueCards[sequence.beginIdx].value !=
            Card.getValue(CardFace.ace)) {
          phoenixCards.add(
            Card.phoenix(uniqueCards[sequence.beginIdx].value + 1),
          );
        } else {
          phoenixCards.add(
            Card.phoenix(uniqueCards[sequence.endIdx].value - 1),
          );
        }
        phoenixStraights.add(TichuTurn(TurnType.straight, phoenixCards));
      }
    }

    // Look for single card gaps in segments add add phoenix there as well.
    for (var i = 1; i < connected.length; ++i) {
      if (uniqueCards[connected[i].beginIdx].value + 2 ==
              uniqueCards[connected[i - 1].endIdx].value &&
          (connected[i].endIdx -
                  connected[i].beginIdx +
                  connected[i - 1].endIdx -
                  connected[i - 1].beginIdx >=
              2)) {
        final phoenixCards = uniqueCards.sublist(
          connected[i - 1].beginIdx,
          connected[i].endIdx + 1,
        );
        phoenixCards.add(
          Card.phoenix(uniqueCards[connected[i].beginIdx].value + 1),
        );
        phoenixStraights.add(TichuTurn(TurnType.straight, phoenixCards));
      }
    }

    straights.addAll(phoenixStraights);
  }

  // Add permutations and filter to desired straight length.
  final allStraights = <TichuTurn>[];
  for (final straight in straights) {
    allStraights.addAll(getStraightPermutations(straight.cards));
  }

  allStraights.retainWhere(
    (final element) => element.cards.length == desiredLength,
  );

  // When having combinations of "pure" straights and phoenix straights, the
  // permutation logic will result in duplicated straights which are removed
  // below to assure unique elements in the list.
  final values = <double>{};
  return allStraights
      .where((final element) => values.add(element.value))
      .toList();
}

// Adds straight permutations which are all possible shorter straight
// combinations that are possible within a longer straight.
List<TichuTurn> getStraightPermutations(final List<Card> cards) {
  assert(isStraight(cards), 'cards must form a valid straight');
  final straightPermutations = <TichuTurn>[TichuTurn(TurnType.straight, cards)];
  var currentPermutationLength = cards.length - 1;

  while (currentPermutationLength >= 5) {
    for (var i = 0; i + currentPermutationLength <= cards.length; ++i) {
      final subSet = cards.sublist(i, i + currentPermutationLength);
      straightPermutations.add(TichuTurn(TurnType.straight, subSet));
    }
    --currentPermutationLength;
  }
  return straightPermutations;
}

// Returns true when the cards form a valid straight.
bool isStraight(final List<Card> cards) {
  var isStraight = true;

  // Straights cannot contain dragon or dog, and must consist of at least five
  // cards.
  if (cards.any(
        (final element) =>
            element.face == CardFace.dragon || element.face == CardFace.dog,
      ) ||
      cards.length < 5) {
    isStraight = false;
  }

  if (isStraight) {
    cards.sort(compareCards);
    var i = 0;

    while (i < cards.length - 1) {
      if (cards[i].value != cards[i + 1].value + 1) {
        isStraight = false;
        break;
      }
      ++i;
    }
  }

  return isStraight;
}
