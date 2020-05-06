import 'package:tichu/view_model/turn/tichu_data.dart';
import 'package:tichu/view_model/turn/utils/card_utils.dart';

List<TichuTurn> getFullHouses(List<Card> cards) {
  List<TichuTurn> fullHouses = [];

  cards.removeWhere((element) =>
      element.face == CardFace.DRAGON || element.face == CardFace.DOG);

  if (cards.length < 5) return fullHouses;

  cards.sort(compareCards);

  Map<CardFace, int> occurrenceCount = getOccurrenceCount(cards);

  List<CardFace> tripledFaces = occurrenceCount.keys
      .where((element) => occurrenceCount[element] >= 3)
      .toList();
  List<CardFace> pairedFaces = occurrenceCount.keys
      .where((element) => occurrenceCount[element] >= 2)
      .toList();

  // TODO there are many full house combinations when color of card is taken
  // into account.
  for (int i = 0; i < tripledFaces.length; ++i) {
    CardFace tripleFace = tripledFaces[i];

    int tripleCount = 0;
    List<Card> fullHouseCards = cards.where((element) {
      if (element.face == tripleFace && tripleCount < 3) {
        ++tripleCount;
        return true;
      }
      return false;
    }).toList();

    List<CardFace> possiblePairs =
        pairedFaces.where((element) => element != tripleFace).toList();

    for (int j = 0; j < possiblePairs.length; ++j) {
      CardFace doubleFace = possiblePairs[j];
      int pairCount = 0;
      List<Card> pair = cards.where((element) {
        if (element.face == doubleFace && pairCount < 2) {
          ++pairCount;
          return true;
        }
        return false;
      }).toList();
      fullHouses.add(TichuTurn(TurnType.FULL_HOUSE, fullHouseCards + pair));
    }
  }

  if (cards.any((element) => element.face == CardFace.PHOENIX)) {
    if (pairedFaces.length >= 2) {
      // We can promote any pair to a triplet and then use any of the other pair
      // to form full house.
    }

    if (tripledFaces.length >= 1) {
      // In that case, we can also form full houses by promoting single card to
      // pair.
    }
  }

  return fullHouses;
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
