import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/bomb_utils.dart';

void main() {
  test('every five-card window of a longer straight flush is a bomb', () {
    final run = [
      for (final f in [
        CardFace.eight,
        CardFace.nine,
        CardFace.ten,
        CardFace.jack,
        CardFace.queen,
        CardFace.king,
      ])
        Card(f, CardColor.green),
    ];
    final bombs = getBombs(run);
    String top(TichuTurn t) =>
        '${t.cards.length}:${t.cards.map((c) => c.value).reduce((a, b) => a > b ? a : b)}';
    expect(bombs.map(top).toSet(), {'6:13.0', '5:12.0', '5:13.0'});
  });
}
