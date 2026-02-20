import 'package:meta/meta.dart';
import 'package:tichu/game/turn/tichu_data.dart';

// Returns number of occurrences of the card face in the list.
int occurrences(final CardFace face, final List<Card> cards) {
  var occurrences = 0;
  for (final card in cards) {
    if (card.face == face) ++occurrences;
  }

  return occurrences;
}

// Returns map containing occurrence information of all cards.
Map<CardFace, int> getOccurrenceCount(final List<Card> cards) {
  final occurrenceCount = <CardFace, int>{};
  for (final card in cards) {
    occurrenceCount.update(card.face, (final value) => value + 1, ifAbsent: () => 1);
  }
  return occurrenceCount;
}

// Returns true when all cards in the list have the same color.
bool uniformColor(final List<Card> cards) {
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

  const ConnectedCards(this.beginIdx, this.endIdx);

  // Override to allow testing
  @override
  bool operator ==(final Object other) => other is ConnectedCards &&
        beginIdx == other.beginIdx &&
        endIdx == other.endIdx;

  @override
  int get hashCode => beginIdx + 5 * endIdx;
}

List<ConnectedCards> findConnectedCards(final List<Card> cards) {
  cards.sort(compareCards);
  final connected = <ConnectedCards>[];
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
