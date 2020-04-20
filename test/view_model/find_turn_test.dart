import 'package:test/test.dart';
import 'package:tichu/view_model/find_turn.dart';
import 'package:tichu/view_model/tichu_data.dart';

void main() {
  group('singles', () {
    Card sampleCard;
    setUp(() {
      sampleCard = Card.FOUR;
    });
    test('getTurnSingle', () {});
  });

// Tests for function isSpecialCard.
  group('isSpecialCard', () {
    test('two', () {
      expect(isSpecialCard([Card.TWO]), false);
    });
    test('dog', () {
      expect(isSpecialCard([Card.DOG]), true);
    });
    test('dragon', () {
      expect(isSpecialCard([Card.DRAGON]), true);
    });
    test('mah jong', () {
      expect(isSpecialCard([Card.MAH_JONG]), true);
    });
  });
}
