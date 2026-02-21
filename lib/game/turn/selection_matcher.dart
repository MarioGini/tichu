import 'package:tichu/game/turn/find_turn.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/card_utils.dart';

bool selectionMatchesTurn(
  final List<Card> turnCards,
  final List<Card> selected,
) {
  if (turnCards.length != selected.length) {
    return false;
  }

  final turnType = getTurn(List<Card>.from(turnCards)).type;
  final isStraightBomb = turnType == TurnType.bomb && turnCards.length > 4;

  if (isStraightBomb) {
    if (!uniformColor(List<Card>.from(selected))) {
      return false;
    }
    if (selected.first.color != turnCards.first.color) {
      return false;
    }
  }

  final turnCounts = _faceCounts(turnCards);
  final selectedCounts = _faceCounts(selected);
  if (turnCounts.length != selectedCounts.length) {
    return false;
  }
  for (final entry in turnCounts.entries) {
    if (selectedCounts[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

Map<CardFace, int> _faceCounts(final List<Card> cards) {
  final counts = <CardFace, int>{};
  for (final card in cards) {
    counts.update(card.face, (final value) => value + 1, ifAbsent: () => 1);
  }
  return counts;
}
