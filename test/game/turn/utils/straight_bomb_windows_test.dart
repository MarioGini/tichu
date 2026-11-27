import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn/find_turn.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/turn_handler.dart';
import 'package:tichu/game/turn/utils/bomb_utils.dart';

void main() {
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

  test('bots get the whole straight flush only', () {
    expect(getBombs(run).map((b) => b.cards.length), [6]);
  });

  test('the shorter bombs inside it are listed for other bots', () {
    final shorter = shorterStraightFlushBombs(run);
    expect(shorter.map((b) => '${b.cards.length}:${b.value}').toSet(), {
      '5:33.0',
      '5:32.0',
    });
  });

  test('a person may still play one: it is a legal bomb', () {
    final eightToQueen = getTurn(run.sublist(0, 5));
    expect(eightToQueen.type, TurnType.bomb);
    final single = getTurn([Card(CardFace.ace, CardColor.red)]);
    expect(validTurn(single, eightToQueen), isTrue);
  });
}
