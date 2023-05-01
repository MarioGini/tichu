import '../tichu_data.dart';
import 'card_utils.dart';

List<TichuTurn> getFullHouses(List<Card> cards) {
  cards.removeWhere((element) =>
      element.face == CardFace.dragon || element.face == CardFace.dog);
  if (cards.length < 5) return [];

  var fullHouses = <TichuTurn>[];
  cards.sort(compareCards);

  var occurrenceCount = getOccurrenceCount(cards);

  var tripledFaces =
      occurrenceCount.keys.where((key) => occurrenceCount[key]! >= 3).toList();
  var pairedFaces =
      occurrenceCount.keys.where((key) => occurrenceCount[key] == 2).toList();

  // TODO there are many full house combinations when color of card is taken
  // into account.
  for (var i = 0; i < tripledFaces.length; ++i) {
    var tripleFace = tripledFaces[i];

    var fullHouseCards = cards.where((card) {
      return card.face == tripleFace;
    }).toList();

    var possiblePairs =
        tripledFaces.where((element) => element != tripleFace).toList();
    possiblePairs.addAll(pairedFaces);

    for (var j = 0; j < possiblePairs.length; ++j) {
      var pair = cards
          .where((card) {
            return card.face == possiblePairs[j];
          })
          .toList()
          .sublist(0, 2);
      fullHouses.add(TichuTurn(TurnType.fullHouse, fullHouseCards + pair));
    }
  }

  if (cards.any((element) => element.face == CardFace.phoenix)) {
    if (pairedFaces.isNotEmpty) {
      // We can promote any pair to a triplet and then use any of the other pair
      // to form full house.
      for (var i = 0; i < pairedFaces.length; ++i) {
        var tripleFace = pairedFaces[i];

        var phoenixCards = cards
            .where((card) {
              return card.face == tripleFace;
            })
            .toList()
            .sublist(0, 2);
        phoenixCards.add(Card.phoenix(phoenixCards.first.value));

        var possiblePairs =
            pairedFaces.where((element) => element != tripleFace).toList();
        possiblePairs.addAll(tripledFaces);

        for (var j = 0; j < possiblePairs.length; ++j) {
          var pair = cards
              .where((card) {
                return card.face == possiblePairs[j];
              })
              .toList()
              .sublist(0, 2);
          fullHouses.add(TichuTurn(TurnType.fullHouse, phoenixCards + pair));
        }
      }
    }

    if (tripledFaces.isNotEmpty) {
      // In that case, we can also form full houses by promoting single card to
      // pair.
      for (var i = 0; i < tripledFaces.length; ++i) {
        var tripleFace = tripledFaces[i];

        var fullHouseCards = cards
            .where((card) {
              return card.face == tripleFace;
            })
            .toList()
            .sublist(0, 3);
        var availablePairs = occurrenceCount.keys
            .where((element) =>
                occurrenceCount[element] == 1 && element != CardFace.phoenix)
            .toList();
        for (var j = 0; j < availablePairs.length; ++j) {
          var pairCard =
              cards.where((element) => element.face == availablePairs[j]).first;
          var phoenix = Card.phoenix(pairCard.value);
          fullHouses.add(TichuTurn(
              TurnType.fullHouse, fullHouseCards + [pairCard, phoenix]));
        }
      }
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
