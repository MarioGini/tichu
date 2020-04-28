import 'package:test/test.dart';
import 'package:tichu/view_model/tichu/find_turn.dart';
import 'package:tichu/view_model/tichu/tichu_data.dart';

void main() {
  group('singles', () {
    CardFace sampleCard;
    setUp(() {
      sampleCard = CardFace.FOUR;
    });
    test('getTurnSingle', () {
      expect(sampleCard == CardFace.FOUR, true);
    });
  });

// Tests for function containsSpecialCard.
  group('containsSpecialCard', () {
    test('two', () {
      expect(containsSpecialCard([Card(CardFace.FIVE, Color.BLACK)]), false);
    });
    test('dog', () {
      expect(containsSpecialCard([Card(CardFace.DOG, Color.SPECIAL)]), true);
    });
    test('dragon', () {
      expect(containsSpecialCard([Card(CardFace.DRAGON, Color.SPECIAL)]), true);
    });
    test('mah jong', () {
      expect(
          containsSpecialCard([Card(CardFace.MAH_JONG, Color.SPECIAL)]), true);
    });
  });
}
