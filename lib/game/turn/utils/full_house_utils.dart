import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/card_utils.dart';

List<TichuTurn> getFullHouses(final List<Card> cards) {
  cards.removeWhere(
    (final element) =>
        element.face == CardFace.dragon || element.face == CardFace.dog,
  );
  if (cards.length < 5) return [];

  final fullHouses = <TichuTurn>[];
  cards.sort(compareCards);

  final occurrenceCount = getOccurrenceCount(cards);

  final tripledFaces = occurrenceCount.keys
      .where((final key) => occurrenceCount[key]! >= 3)
      .toList();
  final pairedFaces = occurrenceCount.keys
      .where((final key) => occurrenceCount[key] == 2)
      .toList();

  // TODO(fullHouse): there are many full house combinations when color of
  // card is taken into account.
  for (var i = 0; i < tripledFaces.length; ++i) {
    final tripleFace = tripledFaces[i];

    final fullHouseCards = cards.where((final card) => card.face == tripleFace).toList();

    final possiblePairs = tripledFaces
        .where((final element) => element != tripleFace)
        .toList();
    possiblePairs.addAll(pairedFaces);

    for (var j = 0; j < possiblePairs.length; ++j) {
      final pair = cards
          .where((final card) => card.face == possiblePairs[j])
          .toList()
          .sublist(0, 2);
      fullHouses.add(TichuTurn(TurnType.fullHouse, fullHouseCards + pair));
    }
  }

  if (cards.any((final element) => element.face == CardFace.phoenix)) {
    if (pairedFaces.isNotEmpty) {
      // We can promote any pair to a triplet and then use any of the other pair
      // to form full house.
      for (var i = 0; i < pairedFaces.length; ++i) {
        final tripleFace = pairedFaces[i];

        final phoenixCards = cards
            .where((final card) => card.face == tripleFace)
            .toList()
            .sublist(0, 2);
        phoenixCards.add(Card.phoenix(phoenixCards.first.value));

        final possiblePairs = pairedFaces
            .where((final element) => element != tripleFace)
            .toList();
        possiblePairs.addAll(tripledFaces);

        for (var j = 0; j < possiblePairs.length; ++j) {
          final pair = cards
              .where((final card) => card.face == possiblePairs[j])
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
        final tripleFace = tripledFaces[i];

        final fullHouseCards = cards
            .where((final card) => card.face == tripleFace)
            .toList()
            .sublist(0, 3);
        final availablePairs = occurrenceCount.keys
            .where(
              (final element) =>
                  occurrenceCount[element] == 1 && element != CardFace.phoenix,
            )
            .toList();
        for (var j = 0; j < availablePairs.length; ++j) {
          final pairCard = cards
              .where((final element) => element.face == availablePairs[j])
              .first;
          final phoenix = Card.phoenix(pairCard.value);
          fullHouses.add(
            TichuTurn(TurnType.fullHouse, fullHouseCards + [pairCard, phoenix]),
          );
        }
      }
    }
  }

  return fullHouses;
}
