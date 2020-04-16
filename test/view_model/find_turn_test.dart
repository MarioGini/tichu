import 'package:test/test.dart';
import 'package:tichu/view_model/find_turn.dart';
import 'package:tichu/view_model/tichu_data.dart';

void main() {
  group('singles', () {
    Card sampleCard;
    setUp(() {
      sampleCard = Card.FOUR;
    });
    test('getTurnSingle', () {
      getTurn([sampleCard]);
      expect(sampleCard, Card.FOUR);
    });
  });
}
