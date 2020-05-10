import 'package:test/test.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';
import 'package:tichu/view_model/turn/turn_handler.dart';

void main() {
  group('validTurn', () {
    test('dragonOnSingleTest', () {
      var deckTurn =
          TichuTurn(TurnType.single, [Card(CardFace.ten, Color.red)]);
      var currentTurn =
          TichuTurn(TurnType.single, [Card(CardFace.dragon, Color.special)]);

      expect(validTurn(deckTurn, currentTurn), true);
    });
    test('bombPairTest', () {
      var deckTurn = TichuTurn(TurnType.pair,
          [Card(CardFace.ten, Color.red), Card(CardFace.ten, Color.blue)]);
      var currentTurn = TichuTurn(TurnType.bomb, [
        Card(CardFace.eight, Color.red),
        Card(CardFace.eight, Color.black),
        Card(CardFace.eight, Color.green),
        Card(CardFace.eight, Color.blue),
      ]);

      expect(validTurn(deckTurn, currentTurn), true);
    });
  });
}
