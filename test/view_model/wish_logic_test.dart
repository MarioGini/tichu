import 'package:test/test.dart';
import "package:tichu/view_model/wish_logic.dart";
import 'package:tichu/view_model/tichu_data.dart';

void main() {
  test('wishIsFullFilledNoWishTest', () {});
  group('computeNextWish', () {
    test('noPreviousWishTest', () {
      CardSelection selection = CardSelection([Card.NINE], null, 0);
      expect(computeNextWish(null, selection), true);
    });
  });
}
