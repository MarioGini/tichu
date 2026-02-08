import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/view_model/turn/tichu_rules.dart';

void main() {
  group('requiredPassesForTrick', () {
    test('returns 0 when activePlayerCount is 0', () {
      expect(requiredPassesForTrick(0), 0);
    });

    test('returns 0 when activePlayerCount is 1', () {
      expect(requiredPassesForTrick(1), 0);
    });

    test('returns 1 when activePlayerCount is 2', () {
      expect(requiredPassesForTrick(2), 1);
    });

    test('returns 2 when activePlayerCount is 3', () {
      expect(requiredPassesForTrick(3), 2);
    });

    test('returns 3 when activePlayerCount is 4 (standard game)', () {
      expect(requiredPassesForTrick(4), 3);
    });
  });
}
