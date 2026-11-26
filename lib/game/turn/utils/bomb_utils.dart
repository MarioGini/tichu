import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/card_utils.dart';

List<TichuTurn> getBombs(List<Card> cards) {
  // Most hands hold no bomb: answer that from bit masks before building any
  // list (the simulator asks this for every hand at every step).
  if (_quickHasBomb(cards) == false) return <TichuTurn>[];
  final bombTurns = <TichuTurn>[];

  // First, look for quartet bombs.
  final occurrenceCount = getOccurrenceCount(cards);
  final bombFaces = occurrenceCount.keys
      .where((element) => occurrenceCount[element] == 4)
      .toList();
  for (final bombFace in bombFaces) {
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

bool hasBombInHand(List<Card> cards) =>
    _quickHasBomb(cards) ?? getBombs(cards).isNotEmpty;

/// Whether [getBombs] finds a bomb in [cards], without building it: a face
/// held exactly four times, or five consecutive values in one colour.
///
/// Null when a colour holds two cards of the same value (impossible with a
/// real deck; then only the full search in [getBombs] is exact, because such
/// a duplicate splits its run).
bool? _quickHasBomb(List<Card> cards) {
  if (cards.length < 4) return false;
  // Bit masks of the faces held at least once / twice / ... / five times.
  var once = 0;
  var twice = 0;
  var thrice = 0;
  var four = 0;
  var five = 0;
  // Per colour: the values present, bit = value + 10 (cards of a suit
  // colour have the integral values -10..25 of their face).
  var black = 0;
  var green = 0;
  var red = 0;
  var blue = 0;
  for (final card in cards) {
    final face = 1 << card.face.index;
    five |= four & face;
    four |= thrice & face;
    thrice |= twice & face;
    twice |= once & face;
    once |= face;
    final color = card.color;
    if (color == CardColor.special) continue;
    final value = card.value.toInt();
    if (value != card.value || value < -10 || value > 25) return null;
    final bit = 1 << (value + 10);
    switch (color) {
      case CardColor.black:
        if (black & bit != 0) return null;
        black |= bit;
      case CardColor.green:
        if (green & bit != 0) return null;
        green |= bit;
      case CardColor.red:
        if (red & bit != 0) return null;
        red |= bit;
      case CardColor.blue:
        if (blue & bit != 0) return null;
        blue |= bit;
      case CardColor.special:
        break;
    }
  }
  if (four & ~five != 0) return true;
  return _hasRunOfFive(black) ||
      _hasRunOfFive(green) ||
      _hasRunOfFive(red) ||
      _hasRunOfFive(blue);
}

bool _hasRunOfFive(int m) => m & (m >> 1) & (m >> 2) & (m >> 3) & (m >> 4) != 0;

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

      // Every run of at least five inside the longest one is a bomb too
      // (8-K holds 8-Q and 9-K): a shorter one keeps the rest in hand.
      for (var from = start; from + 4 <= end; from++) {
        for (var to = from + 4; to <= end; to++) {
          bombs.add(TichuTurn(TurnType.bomb, colorCards.sublist(from, to + 1)));
        }
      }

      start = end + 1;
    }
  }

  return bombs;
}
