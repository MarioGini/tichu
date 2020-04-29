import 'package:tichu/view_model/tichu/tichu_data.dart';

bool canPlayCard(Card card, double value) {
  return card.value > value;
}

// Returns true when the cards are in order as required for a straight, and do
// not contain a dragon or dog.
bool areOrdered(List<Card> cards) {
  cards.sort(compareCards);
  bool cardsAreOrdered = true;
  int i = 1;
  while (i <= cards.length - 1) {
    if (cards[i].value != cards[i - 1].value - 1) {
      cardsAreOrdered = false;
      break;
    }
    ++i;
  }

  // Make sure that dragon and dog are not contained in list.
  cardsAreOrdered = cards.every((element) =>
      element.face != CardFace.DRAGON && element.face != CardFace.DOG);

  return cardsAreOrdered;
}

// Returns true when all cards in the list have the same color.
bool uniformColor(List<Card> cards) {
  bool uniformColor = true;
  int i = 1;
  while (i <= cards.length - 1) {
    if (cards[i].color != cards[i - 1].color) {
      uniformColor = false;
      break;
    }
    ++i;
  }

  return uniformColor;
}

// Returns list of cards that are doubles, sorted.
List<CardFace> getPairs(List<Card> cards) {
  List<CardFace> pairs = [];

  cards.sort(compareCards);
  return pairs;
}

// Returns list of cards that are triplets, sorted.
List<CardFace> getTriplets(List<Card> cards) {
  List<CardFace> triplets = [];

  return triplets;
}

List<CardFace> getQuartets(List<Card> cards) {
  List<CardFace> quartets = [];

  return quartets;
}
