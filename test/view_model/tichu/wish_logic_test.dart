import 'package:test/test.dart';
import "package:tichu/view_model/tichu/wish_logic.dart";
import 'package:tichu/view_model/tichu/tichu_data.dart';

void main() {
  test('wishIsFullFilledNoWishTest', () {});
  group('computeNextWish', () {
    test('noPreviousWishTest', () {
      CardSelection selection = CardSelection([Card.NINE], null, 0);
      expect(computeNextWish(null, selection), true);
    });
  });

  group('canPlayWishTest', () {
    test('canPlayWishOnSingleTest', () {});
    test('canPlayWishOnPairTest', () {});
  });
}
