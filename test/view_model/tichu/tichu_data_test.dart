import 'package:test/test.dart';
import 'package:tichu/view_model/tichu/tichu_data.dart';

void main() {
  group('CardEnum', () {
    // Tests to assert that the card enumeration is correctly ordered.
    test('mahJong', () {
      expect(Card.MAH_JONG.index, 0);
    });
    test('twoTest', () {
      expect(Card.TWO.index, 1);
    });
    test('threeTest', () {
      expect(Card.THREE.index, 2);
    });
    test('fourTest', () {
      expect(Card.FOUR.index, 3);
    });
    test('fiveTest', () {
      expect(Card.FIVE.index, 4);
    });
    test('sixTest', () {
      expect(Card.SIX.index, 5);
    });
    test('sevenTest', () {
      expect(Card.SEVEN.index, 6);
    });
    test('eightTest', () {
      expect(Card.EIGHT.index, 7);
    });
    test('nineTest', () {
      expect(Card.NINE.index, 8);
    });
    test('tenTest', () {
      expect(Card.TEN.index, 9);
    });
    test('jackTest', () {
      expect(Card.JACK.index, 10);
    });
    test('queenTest', () {
      expect(Card.QUEEN.index, 11);
    });
    test('kingTest', () {
      expect(Card.KING.index, 12);
    });
    test('aceTest', () {
      expect(Card.ACE.index, 13);
    });
    test('dragonTest', () {
      expect(Card.DRAGON.index, 14);
    });
  });
  test('Sorting test', () {
    List<Card> testCards = [Card.DOG, Card.TEN, Card.EIGHT, Card.PHOENIX];
    testCards.sort(compareCards);

    List<Card> expectedOrder = [Card.DOG, Card.PHOENIX, Card.TEN, Card.EIGHT];
    expect(testCards, expectedOrder);
  });

  group('GetTurnTests', () {
    test('SingleCardTests', () {});
  });
}
