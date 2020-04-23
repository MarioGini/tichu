import 'package:test/test.dart';
import "package:tichu/view_model/tichu/card_utils.dart";
import 'package:tichu/view_model/tichu/tichu_data.dart';

void main() {
  group('getTriplets', () {
    test('noTripletTest', () {
      Map<Card, int> cards = {Card.EIGHT: 2, Card.JACK: 1};
      expect(getTriplets(cards), []);
    });
    test('twoTripletTest', () {
      Map<Card, int> cards = {Card.EIGHT: 3, Card.JACK: 2, Card.QUEEN: 3};
      expect(getTriplets(cards), [Card.QUEEN, Card.EIGHT]);
    });
  });
}
