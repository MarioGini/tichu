import 'package:tichu/view_model/tichu/tichu_data.dart';

bool canPlayCard(Card card, double value) {
  return card.value > value;
}

// Returns list of cards that are doubles, sorted.
List<Card> getPairs(List<Card> cards) {
  List<Card> pairs = [];

  pairs.sort(compareCards);
  return pairs;
}

// Returns list of cards that are triplets, sorted.
List<Card> getTriplets(List<Card> cards) {
  List<Card> triplets = [];

  triplets.sort(compareCards);
  return triplets;
}

List<Card> getQuartets(List<Card> cards) {
  List<Card> quartets = [];

  quartets.sort(compareCards);
  return quartets;
}
