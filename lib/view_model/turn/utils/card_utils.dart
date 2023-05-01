import 'package:flutter/foundation.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';

// Returns number of occurrences of the card face in the list.
int occurrences(CardFace face, List<Card> cards) {
  var occurrences = 0;
  for (var card in cards) {
    if (card.face == face) ++occurrences;
  }

  return occurrences;
}

// Returns map containing occurrence information of all cards.
Map<CardFace, int> getOccurrenceCount(List<Card> cards) {
  var occurrenceCount = <CardFace, int>{};
  for (var card in cards) {
    occurrenceCount.update(
      card.face,
      (value) => ++value,
      ifAbsent: () => 1,
    );
  }
  return occurrenceCount;
}

// Returns true when all cards in the list have the same color.
bool uniformColor(List<Card> cards) {
  var uniformColor = true;
  var i = 0;
  while (i <= cards.length - 2) {
    if (cards[i].color != cards[i + 1].color) {
      uniformColor = false;
      break;
    }
    ++i;
  }

  return uniformColor;
}

@immutable
class ConnectedCards {
  final int beginIdx;
  final int endIdx;

  ConnectedCards(this.beginIdx, this.endIdx);

  // Override to allow testing
  @override
  bool operator ==(dynamic other) {
    return other is ConnectedCards &&
        beginIdx == other.beginIdx &&
        endIdx == other.endIdx;
  }

  @override
  int get hashCode {
    return beginIdx + 5 * endIdx;
  }
}

List<ConnectedCards> findConnectedCards(List<Card> cards) {
  cards.sort(compareCards);
  var connected = <ConnectedCards>[];
  var beginIdx = 0;
  var endIdx = 0;

  for (var i = 1; i < cards.length; ++i) {
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
