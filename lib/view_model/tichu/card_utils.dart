import 'package:tichu/view_model/tichu/tichu_data.dart';

bool canPlayCard(Card card, double value) {
  return card.index > value;
}

// Returns list of cards that are doubles, sorted.
List<Card> getPairs(Map<Card, int> cards) {
  List<Card> pairs = [];
  cards.forEach((key, value) {
    if (value == 2) pairs.add(key);
  });
  pairs.sort(compareCards);
  return pairs;
}

// Returns list of cards that are triplets, sorted.
List<Card> getTriplets(Map<Card, int> cards) {
  List<Card> triplets = [];
  cards.forEach((key, value) {
    if (value == 3) triplets.add(key);
  });
  triplets.sort(compareCards);
  return triplets;
}

List<Card> getQuartets(Map<Card, int> cards) {
  List<Card> quartets = [];
  cards.forEach((key, value) {
    if (value == 4) quartets.add(key);
  });
  quartets.sort(compareCards);
  return quartets;
}
