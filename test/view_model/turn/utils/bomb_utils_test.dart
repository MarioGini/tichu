import 'package:test/test.dart';
import "package:tichu/view_model/turn/utils/bomb_utils.dart";
import 'package:tichu/view_model/turn/tichu_data.dart';

void main() {
  group('getBombs', () {
    test('twoQuartetBombTest', () {
      var cards = <Card>[
        Card(CardFace.eight, Color.black),
        Card(CardFace.eight, Color.green),
        Card(CardFace.eight, Color.red),
        Card(CardFace.eight, Color.blue),
        Card(CardFace.jack, Color.black),
        Card(CardFace.jack, Color.green),
        Card(CardFace.jack, Color.red),
        Card(CardFace.jack, Color.blue)
      ];

      var turns = getBombs(cards);
      expect(turns.length, 2);
      expect(turns.every((turn) => isBomb(turn.cards)), true);
      expect(turns.any((turn) => turn.value == Card.getValue(CardFace.eight)),
          true);
      expect(turns.any((turn) => turn.value == Card.getValue(CardFace.jack)),
          true);
    });
    test('noBombTest', () {
      var cards = <Card>[
        Card(CardFace.eight, Color.black),
        Card(CardFace.eight, Color.green),
        Card(CardFace.eight, Color.red),
        Card(CardFace.jack, Color.black),
        Card(CardFace.jack, Color.green),
      ];

      var turns = getBombs(cards);
      expect(turns.length, 0);
    });
  });
  group('isBomb', () {
    test('quartetBombTest', () {
      var cards = <Card>[
        Card(CardFace.eight, Color.black),
        Card(CardFace.eight, Color.green),
        Card(CardFace.eight, Color.red),
        Card(CardFace.eight, Color.blue),
      ];

      expect(isBomb(cards), true);
    });
    test('straightBombTest', () {
      var cards = <Card>[
        Card(CardFace.eight, Color.black),
        Card(CardFace.nine, Color.black),
        Card(CardFace.ten, Color.black),
        Card(CardFace.jack, Color.black),
        Card(CardFace.queen, Color.black),
        Card(CardFace.king, Color.black)
      ];

      expect(isBomb(cards), true);
    });
  });
}
