import 'package:tichu/view_model/turn/tichu_data.dart';
import 'package:tichu/view_model/turn/utils/card_utils.dart';
import 'package:tichu/view_model/turn/utils/straight_utils.dart';

List<TichuTurn> getBombs(List<Card> cards) {
  List<TichuTurn> bombTurns = [];

  // First, look for quartet bombs.
  Map<CardFace, int> occurrenceCount = getOccurrenceCount(cards);
  List<CardFace> bombFaces = occurrenceCount.keys
      .where((element) => occurrenceCount[element] == 4)
      .toList();
  if (bombFaces.length != 0) {
    bombFaces.forEach((bombFace) {
      bombTurns.add(TichuTurn(TurnType.BOMB,
          cards.where((card) => card.face == bombFace).toList()));
    });
  }

  // Look for straight bombs.
  // TODO how to look for random length?
  List<TichuTurn> straightBombs = getStraights(cards, 5);
  straightBombs.forEach((element) {
    if (uniformColor(element.cards)) {
      bombTurns.add(element);
    }
  });

  return bombTurns;
}

bool isBomb(List<Card> cards) {
  bool isBomb = false;
  if (cards.length == 4 && getOccurrenceCount(cards).keys.length == 1) {
    isBomb = true;
  } else if (isStraight(cards) && uniformColor(cards)) {
    isBomb = true;
  }

  return isBomb;
}
