import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/nn/nn_schupf_strategy.dart';
import 'package:tichu/agents/tichu_call_strategy.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'ai_test_fixtures.dart';

void main() {
  const strategy = DefaultTichuCallStrategy();

  test('grand tichu needs strength 5 in the first eight cards', () async {
    Card card(final CardFace f, [final CardColor c = CardColor.red]) =>
        Card(f, c);
    final fillers = [
      card(CardFace.two),
      card(CardFace.three, CardColor.blue),
      card(CardFace.five, CardColor.green),
      card(CardFace.seven, CardColor.black),
    ];
    Future<bool> call(final List<Card> strong) => strategy.shouldCallGrandTichu(
      aiSnapshot(myHand: [...strong, ...fillers].take(8).toList()),
      aiTestSelfId,
    );
    // Phoenix + two aces = 5.
    expect(
      await call([
        card(CardFace.phoenix, CardColor.special),
        card(CardFace.ace),
        card(CardFace.ace, CardColor.blue),
        card(CardFace.nine),
      ]),
      isTrue,
    );
    // The Dog costs one: 4.
    expect(
      await call([
        card(CardFace.phoenix, CardColor.special),
        card(CardFace.ace),
        card(CardFace.ace, CardColor.blue),
        card(CardFace.dog, CardColor.special),
      ]),
      isFalse,
    );
    expect(
      DefaultTichuCallStrategy.grandStrength([
        card(CardFace.dragon, CardColor.special),
        card(CardFace.ace),
        card(CardFace.king),
        card(CardFace.queen),
        card(CardFace.queen, CardColor.blue),
      ]),
      closeTo(5, 1e-9),
    );
  });

  test('tichu follows paper index threshold (It >= 7)', () async {
    final belowThreshold = aiSnapshot(
      myHand: [
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.dog, CardColor.special),
        Card(CardFace.two, CardColor.blue),
        Card(CardFace.three, CardColor.green),
        Card(CardFace.four, CardColor.black),
        Card(CardFace.five, CardColor.red),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.seven, CardColor.green),
        Card(CardFace.eight, CardColor.black),
        Card(CardFace.nine, CardColor.red),
        Card(CardFace.ten, CardColor.blue),
        Card(CardFace.jack, CardColor.green),
        Card(CardFace.queen, CardColor.black),
        Card(CardFace.king, CardColor.red),
      ],
    );

    final atOrAboveThreshold = aiSnapshot(
      myHand: [
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.ace, CardColor.blue),
        Card(CardFace.dragon, CardColor.special),
        Card(CardFace.king, CardColor.red),
        Card(CardFace.king, CardColor.blue),
        Card(CardFace.king, CardColor.green),
        Card(CardFace.king, CardColor.black),
        Card(CardFace.queen, CardColor.red),
        Card(CardFace.queen, CardColor.blue),
        Card(CardFace.jack, CardColor.green),
        Card(CardFace.jack, CardColor.black),
        Card(CardFace.ten, CardColor.red),
        Card(CardFace.ten, CardColor.blue),
        Card(CardFace.nine, CardColor.green),
      ],
    );

    expect(
      await strategy.shouldCallTichu(belowThreshold, aiTestSelfId),
      isFalse,
    );
    expect(
      await strategy.shouldCallTichu(atOrAboveThreshold, aiTestSelfId),
      isTrue,
    );
  });

  test('extended schupf candidates may pass a weak card to the partner', () {
    final hand = [
      Card(CardFace.dragon, CardColor.special),
      Card(CardFace.ace, CardColor.red),
      Card(CardFace.king, CardColor.red),
      Card(CardFace.queen, CardColor.red),
      Card(CardFace.jack, CardColor.red),
      Card(CardFace.ten, CardColor.red),
      Card(CardFace.nine, CardColor.blue),
      Card(CardFace.eight, CardColor.blue),
      Card(CardFace.seven, CardColor.blue),
      Card(CardFace.six, CardColor.green),
      Card(CardFace.five, CardColor.green),
      Card(CardFace.four, CardColor.green),
      Card(CardFace.three, CardColor.black),
      Card(CardFace.two, CardColor.black),
    ];
    Set<CardFace> partnerFaces({required final bool extended}) => {
      for (final (_, p, _) in SchupfFeatures.candidates(
        hand,
        extended: extended,
      ))
        hand[p].face,
    };
    expect(partnerFaces(extended: false), isNot(contains(CardFace.two)));
    expect(
      partnerFaces(extended: true),
      containsAll([CardFace.two, CardFace.three, CardFace.dragon]),
    );
  });
}
