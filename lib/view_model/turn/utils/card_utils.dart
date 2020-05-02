import 'package:tichu/view_model/turn/tichu_data.dart';

// Returns number of occurrences of the card face in the list.
int occurrences(CardFace face, List<Card> cards) {
  int occurrences = 0;
  cards.forEach((element) {
    if (element.face == face) ++occurrences;
  });

  return occurrences;
}

// Returns true when all cards in the list have the same color.
bool uniformColor(List<Card> cards) {
  bool uniformColor = true;
  int i = 0;
  while (i <= cards.length - 2) {
    if (cards[i].color != cards[i + 1].color) {
      uniformColor = false;
      break;
    }
    ++i;
  }

  return uniformColor;
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
