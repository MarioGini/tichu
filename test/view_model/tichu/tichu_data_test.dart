import 'package:test/test.dart';
import 'package:tichu/view_model/tichu/tichu_data.dart';

void main() {
  group('CardEnum', () {
    // Tests to assert that the card enumeration is correctly ordered.
    test('mahJong', () {
      expect(Card.MAH_JONG.index, 1);
    });
    test('twoTest', () {
      expect(Card.TWO.index, 2);
    });
    test('threeTest', () {
      expect(Card.THREE.index, 3);
    });
    test('fourTest', () {
      expect(Card.FOUR.index, 4);
    });
    test('fiveTest', () {
      expect(Card.FIVE.index, 5);
    });
    test('sixTest', () {
      expect(Card.SIX.index, 6);
    });
    test('sevenTest', () {
      expect(Card.SEVEN.index, 7);
    });
    test('eightTest', () {
      expect(Card.EIGHT.index, 8);
    });
    test('nineTest', () {
      expect(Card.NINE.index, 9);
    });
    test('tenTest', () {
      expect(Card.TEN.index, 10);
    });
    test('jackTest', () {
      expect(Card.JACK.index, 11);
    });
    test('queenTest', () {
      expect(Card.QUEEN.index, 12);
    });
    test('kingTest', () {
      expect(Card.KING.index, 13);
    });
    test('aceTest', () {
      expect(Card.ACE.index, 14);
    });
    test('dragonTest', () {
      expect(Card.DRAGON.index, 15);
    });
  });
  test('Sorting test', () {
    List<Card> testCards = [Card.DOG, Card.TEN, Card.EIGHT, Card.PHOENIX];
    testCards.sort(compareCards);

    List<Card> expectedOrder = [Card.EIGHT, Card.TEN, Card.PHOENIX, Card.DOG];
    expect(testCards, expectedOrder);
  });

  group('GetTurnTests', () {
    test('SingleCardTests', () {});
  });
}
