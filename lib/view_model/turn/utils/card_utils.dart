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

class ConnectedCards {
  int beginIdx;
  int endIdx;

  ConnectedCards(
    this.beginIdx,
    this.endIdx,
  );

  // Override to allow testing
  @override
  bool operator ==(other) {
    return other is ConnectedCards &&
        this.beginIdx == other.beginIdx &&
        this.endIdx == other.endIdx;
  }

  @override
  int get hashCode {
    return beginIdx + 5 * endIdx;
  }
}

List<ConnectedCards> findConnectedCards(List<Card> cards) {
  cards.sort(compareCards);
  List<ConnectedCards> connected = [];
  int beginIdx = 0;
  int endIdx = 0;

  for (int i = 1; i < cards.length; ++i) {
    if (cards[i].value + 1 != cards[i - 1].value) {
      connected.add(ConnectedCards(beginIdx, endIdx));
      beginIdx = i;
    }
    endIdx = i;
  }
  if (endIdx == cards.length - 1) {
    connected.add(ConnectedCards(beginIdx, endIdx));
  }

  return connected;
}