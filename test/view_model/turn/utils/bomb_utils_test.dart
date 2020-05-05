import 'package:test/test.dart';
import "package:tichu/view_model/turn/utils/bomb_utils.dart";
import 'package:tichu/view_model/turn/tichu_data.dart';

void main() {
  group('getBombs', () {
    test('twoQuartetBombTest', () {
      List<Card> cards = [
        Card(CardFace.EIGHT, Color.BLACK),
        Card(CardFace.EIGHT, Color.GREEN),
        Card(CardFace.EIGHT, Color.RED),
        Card(CardFace.EIGHT, Color.BLUE),
        Card(CardFace.JACK, Color.BLACK),
        Card(CardFace.JACK, Color.GREEN),
        Card(CardFace.JACK, Color.RED),
        Card(CardFace.JACK, Color.BLUE)
      ];

      List<TichuTurn> turns = getBombs(cards);
      expect(turns.length, 2);
      expect(turns.every((turn) => isBomb(turn.cards)), true);
      expect(turns.any((turn) => turn.value == Card.getValue(CardFace.EIGHT)),
          true);
      expect(turns.any((turn) => turn.value == Card.getValue(CardFace.JACK)),
          true);
    });
  });
  group('isBomb', () {
    test('quartetBombTest', () {
      List<Card> cards = [
        Card(CardFace.EIGHT, Color.BLACK),
        Card(CardFace.EIGHT, Color.GREEN),
        Card(CardFace.EIGHT, Color.RED),
        Card(CardFace.EIGHT, Color.BLUE),
      ];

      expect(isBomb(cards), true);
    });
    test('straightBombTest', () {
      List<Card> cards = [
        Card(CardFace.EIGHT, Color.BLACK),
        Card(CardFace.NINE, Color.BLACK),
        Card(CardFace.TEN, Color.BLACK),
        Card(CardFace.JACK, Color.BLACK),
        Card(CardFace.QUEEN, Color.BLACK),
        Card(CardFace.KING, Color.BLACK)
      ];

      expect(isBomb(cards), true);
    });
  });
}
