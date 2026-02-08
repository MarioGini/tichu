import '../tichu_data.dart';
import 'card_utils.dart';

List<TichuTurn> getBombs(List<Card> cards) {
  var bombTurns = <TichuTurn>[];

  // First, look for quartet bombs.
  var occurrenceCount = getOccurrenceCount(cards);
  var bombFaces = occurrenceCount.keys
      .where((element) => occurrenceCount[element] == 4)
      .toList();
  for (var bombFace in bombFaces) {
    bombTurns.add(
      TichuTurn(
        TurnType.bomb,
        cards.where((card) => card.face == bombFace).toList(),
      ),
    );
  }

  // Look for straight bombs.
  bombTurns.addAll(_getStraightBombs(cards));

  return bombTurns;
}

bool hasBombInHand(List<Card> cards) {
  return getBombs(cards).isNotEmpty;
}

List<TichuTurn> _getStraightBombs(List<Card> cards) {
  final bombs = <TichuTurn>[];
  final suitedCards = cards
      .where((card) => card.color != CardColor.special)
      .toList();
  final colors = CardColor.values.where((color) => color != CardColor.special);

  for (final color in colors) {
    final colorCards = suitedCards.where((card) => card.color == color).toList()
      ..sort(compareCards);
    if (colorCards.length < 5) continue;

    var start = 0;
    while (start < colorCards.length) {
      var end = start;
      while (end + 1 < colorCards.length &&
          colorCards[end].value == colorCards[end + 1].value + 1) {
        end++;
      }

      if (end - start + 1 >= 5) {
        bombs.add(TichuTurn(TurnType.bomb, colorCards.sublist(start, end + 1)));
      }

      start = end + 1;
    }
  }

  return bombs;
}
