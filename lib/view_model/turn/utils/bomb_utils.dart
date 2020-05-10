import '../tichu_data.dart';
import 'card_utils.dart';
import 'straight_utils.dart';

List<TichuTurn> getBombs(List<Card> cards) {
  var bombTurns = <TichuTurn>[];

  // First, look for quartet bombs.
  var occurrenceCount = getOccurrenceCount(cards);
  var bombFaces = occurrenceCount.keys
      .where((element) => occurrenceCount[element] == 4)
      .toList();
  for (var bombFace in bombFaces) {
    bombTurns.add(TichuTurn(
        TurnType.bomb, cards.where((card) => card.face == bombFace).toList()));
  }

  // Look for straight bombs.
  // TODO how to look for random length?
  var straightBombs = getStraights(cards, 5);
  for (var straightBomb in straightBombs) {
    if (uniformColor(straightBomb.cards)) {
      bombTurns.add(straightBomb);
    }
  }

  return bombTurns;
}

bool isBomb(List<Card> cards) {
  var isBomb = false;
  if (cards.length == 4 && getOccurrenceCount(cards).keys.length == 1) {
    isBomb = true;
  } else if (isStraight(cards) && uniformColor(cards)) {
    isBomb = true;
  }

  return isBomb;
}
