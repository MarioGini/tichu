import 'package:tichu/view_model/turn/tichu_data.dart';

// Returns number of occurrences of the card face in the list.
int occurrences(CardFace face, List<Card> cards) {
  int occurrences = 0;
  cards.forEach((element) {
    if (element.face == face) ++occurrences;
  });

  return occurrences;
}

// Returns map containing occurrence information of all cards.
Map<CardFace, int> getOccurrenceCount(List<Card> cards) {
  Map<CardFace, int> occurrenceCount = {};
  cards.forEach((element) {
    if (occurrenceCount.containsKey(element.face)) {
      ++occurrenceCount[element.face];
    } else {
      occurrenceCount[element.face] = 1;
    }
  });

  return occurrenceCount;
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
