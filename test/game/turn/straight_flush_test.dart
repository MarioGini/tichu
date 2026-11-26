import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn/find_turn.dart';
import 'package:tichu/game/turn/move_generator.dart';
import 'package:tichu/game/turn/tichu_data.dart';

void main() {
  DeckState lead() =>
      DeckState(TichuTurn(TurnType.empty, const []), CardFace.none);
  final flush = [
    Card(CardFace.six, CardColor.green),
    Card(CardFace.seven, CardColor.green),
    Card(CardFace.eight, CardColor.green),
    Card(CardFace.nine, CardColor.green),
    Card(CardFace.ten, CardColor.green),
  ];
  bool oneSuit(TichuTurn t) => t.cards.every((c) => c.color == CardColor.green);

  test('a straight in one suit is only a bomb', () {
    final turns = generateLegalTurns(lead(), List.of(flush));
    expect(
      turns.where((t) => t.type == TurnType.straight && t.cards.length == 5),
      isEmpty,
    );
    expect(turns.where((t) => t.type == TurnType.bomb), hasLength(1));
  });

  test('another suit of a rank makes the plain straight', () {
    final hand = [...flush, Card(CardFace.eight, CardColor.red)];
    final straights = generateLegalTurns(
      lead(),
      hand,
    ).where((t) => t.type == TurnType.straight).toList();
    expect(straights, isNotEmpty);
    expect(straights.where(oneSuit), isEmpty);
  });

  test('played by a person, it is a bomb', () {
    expect(getTurn(List.of(flush)).type, TurnType.bomb);
  });
}
