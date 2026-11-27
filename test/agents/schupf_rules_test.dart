import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/nn/nn_schupf_strategy.dart';
import 'package:tichu/agents/schupf_strategy.dart';
import 'package:tichu/game/card_identifiers.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'ai_test_fixtures.dart';

void main() {
  final deck = cardIdentifiers.values.toList();
  final hands = [
    for (var i = 0; i < 300; i++)
      (deck.toList()..shuffle(Random(i))).take(14).toList(),
  ];
  final withMahJong = hands
      .where((h) => h.any((c) => c.face == CardFace.mahJong))
      .toList();

  test('the net never gets a pass with the Mah Jong to an opponent', () {
    expect(withMahJong, isNotEmpty);
    for (final hand in withMahJong) {
      for (final mode in [(false, false), (true, false), (false, true)]) {
        for (final (l, _, r) in SchupfFeatures.candidates(
          hand,
          extended: mode.$1,
          all: mode.$2,
        )) {
          expect(hand[l].face, isNot(CardFace.mahJong));
          expect(hand[r].face, isNot(CardFace.mahJong));
        }
      }
    }
  });

  test('the heuristic never passes the Mah Jong to an opponent', () async {
    const strategy = DefaultSchupfStrategy();
    for (final hand in withMahJong) {
      final pass = await strategy.selectSchupfCards(
        aiSnapshot(myHand: hand),
        aiTestSelfId,
      );
      expect(
        SchupfRules.allows(pass.toLeft, pass.toPartner, pass.toRight),
        isTrue,
      );
    }
  });
}
