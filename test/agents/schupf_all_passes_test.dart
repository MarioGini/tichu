import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/nn/nn_schupf_strategy.dart';
import 'package:tichu/game/card_identifiers.dart';

void main() {
  test('every pass of a full hand is a candidate', () {
    final hand = cardIdentifiers.values.take(14).toList();
    final all = SchupfFeatures.candidates(hand, all: true);
    expect(all, hasLength(14 * 13 * 12));
    expect(all.toSet(), hasLength(all.length));
    for (final (l, p, r) in all) {
      expect({l, p, r}, hasLength(3));
    }
  });
}
