import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/card_knowledge.dart';
import 'package:tichu/agents/claim_analysis.dart';
import 'package:tichu/game/turn/move_generator.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'ai_test_fixtures.dart';
import 'feature_encoder_fixtures.dart';

const List<CardColor> _suits = [
  CardColor.black,
  CardColor.green,
  CardColor.red,
  CardColor.blue,
];

/// Unseen counts per rank (index 1 = Mah Jong, 2..14) from (rank, count).
List<int> unseen(Map<int, int> counts) {
  final u = List<int>.filled(15, 0);
  counts.forEach((r, n) => u[r] = n);
  return u;
}

/// Every rank fully unseen (start of a round).
List<int> allUnseen() => [0, 1, for (var r = 2; r <= 14; r++) 4];

int s(CardFace face, [CardColor color = CardColor.black]) =>
    cardSlot(c(face, color));

const int phoenix = CardKnowledge.phoenixSlot;
const int dragon = CardKnowledge.dragonSlot;
const int dog = CardKnowledge.dogSlot;
const int mahJong = CardKnowledge.mahJongSlot;

/// Every lead partition of [hand] by brute force on the card level: the
/// combination holding the lowest remaining card (by rank, the Phoenix
/// last) is one of the move generator's leads of the remaining cards;
/// [CardKnowledge]'s beatability. (min beatable, max unbeatable); the Dog
/// counts as beatable.
(int, int) referenceClaim(List<Card> hand, CardKnowledge k) {
  final memo = <String, int>{};
  final deck = DeckState(TichuTurn(TurnType.empty, const []), CardFace.none);
  int order(Card card) => switch (card.face) {
    CardFace.phoenix => 99,
    CardFace.dragon => 50,
    CardFace.dog => 0,
    _ => faceRank(card.face),
  };
  int solve(List<Card> rest) {
    if (rest.isEmpty) return 0;
    final key = (rest.map(cardSlot).toList()..sort()).join(',');
    final hit = memo[key];
    if (hit != null) return hit;
    var low = rest.first;
    for (final card in rest) {
      if (order(card) < order(low)) low = card;
    }
    final anchor = cardSlot(low);
    var best = 1 << 20;
    for (final turn in [
      ...generateLegalTurns(deck, rest),
      ...straightFlushRuns(rest),
    ]) {
      final slots = turn.cards.map(cardSlot).toSet();
      if (!slots.contains(anchor)) continue;
      // Generator quirk: Phoenix padding below a pair of twos makes a
      // "pair" of Mah Jong + Phoenix; not a legal Tichu combination.
      if (turn.type == TurnType.pairStraight &&
          turn.cards.any((x) => x.face == CardFace.mahJong)) {
        continue;
      }
      final remaining = [
        for (final card in rest)
          if (!slots.contains(cardSlot(card))) card,
      ];
      final isDog =
          turn.cards.length == 1 && turn.cards.first.face == CardFace.dog;
      final beatable = isDog || k.canBeBeaten(turn);
      final v = (beatable ? 64 : -1) + solve(remaining);
      if (v < best) best = v;
    }
    return memo[key] = best;
  }

  final score = solve(hand);
  final b = (score + 63) ~/ 64;
  return (b, 64 * b - score);
}

/// Every run of >= 5 consecutive cards of one colour in [cards], as bombs
/// (the generator lists only the longest run per colour).
List<TichuTurn> straightFlushRuns(List<Card> cards) => [
  for (final color in _suits)
    for (var lo = 2; lo <= 10; lo++)
      for (var hi = lo + 4; hi <= 14; hi++)
        if ([
          for (var r = lo; r <= hi; r++)
            cards.any((x) => x.color == color && faceRank(x.face) == r),
        ].every((held) => held))
          TichuTurn(TurnType.bomb, [
            for (final x in cards)
              if (x.color == color &&
                  faceRank(x.face) >= lo &&
                  faceRank(x.face) <= hi)
                x,
          ]),
];

void main() {
  group('ClaimSolver on hand-built positions', () {
    test('A + A once Dragon and Phoenix are out and no ace unseen', () {
      final hand = [s(CardFace.ace), s(CardFace.ace, CardColor.red)];
      final out = ClaimSolver.fromUnseen(
        unseenRank: unseen({13: 3, 5: 2}),
        phoenix: false,
        dragon: false,
      ).ofSlots(hand);
      expect(out.minBeatable, 0);
      expect(out.unbeatable, 2); // two unbeatable singles
      expect(out.claimable, isTrue);

      // Dragon unseen: the singles can be beaten, the pair cannot.
      final withDragon = ClaimSolver.fromUnseen(
        unseenRank: unseen({13: 3}),
        phoenix: false,
        dragon: true,
      ).ofSlots(hand);
      expect(withDragon.minBeatable, 0);
      expect(withDragon.unbeatable, 1);
    });

    test('a pair of kings becomes unbeatable once the aces are gone', () {
      final hand = [
        s(CardFace.king),
        s(CardFace.king, CardColor.red),
        s(CardFace.five),
      ];
      final twoAces = ClaimSolver.fromUnseen(
        unseenRank: unseen({14: 2, 9: 3}),
        phoenix: false,
        dragon: false,
      ).ofSlots(hand);
      expect(twoAces.minBeatable, 2);
      expect(twoAces.claimable, isFalse);

      final oneAce = ClaimSolver.fromUnseen(
        unseenRank: unseen({14: 1, 9: 3}),
        phoenix: false,
        dragon: false,
      ).ofSlots(hand);
      expect(oneAce.minBeatable, 1);
      expect(oneAce.unbeatable, 1);
      expect(oneAce.claimable, isTrue);

      // One ace plus the Phoenix unseen form a higher pair.
      final acePhoenix = ClaimSolver.fromUnseen(
        unseenRank: unseen({14: 1, 9: 3}),
        phoenix: true,
        dragon: false,
      ).ofSlots(hand);
      expect(acePhoenix.minBeatable, 2);
    });

    test('two beatable combinations are not claimable', () {
      final out = ClaimSolver.fromUnseen(
        unseenRank: allUnseen(),
        phoenix: true,
        dragon: true,
      ).ofSlots([s(CardFace.three), s(CardFace.seven), s(CardFace.dragon)]);
      expect(out.minBeatable, 2);
      expect(out.unbeatable, 1);
      expect(out.claimable, isFalse);
    });

    test('the Phoenix as a wildcard', () {
      final solver = ClaimSolver.fromUnseen(
        unseenRank: allUnseen(),
        phoenix: false,
        dragon: true,
      );
      // Ace + Phoenix = a pair of aces: unbeatable.
      expect(
        solver.ofSlots([s(CardFace.ace), phoenix]),
        isA<ClaimResult>()
            .having((r) => r.minBeatable, 'minBeatable', 0)
            .having((r) => r.unbeatable, 'unbeatable', 1),
      );
      // 10 J Q K + Phoenix = a straight to the ace, unbeatable; + a 4.
      final straight = solver.ofSlots([
        s(CardFace.ten),
        s(CardFace.jack, CardColor.red),
        s(CardFace.queen),
        s(CardFace.king, CardColor.blue),
        phoenix,
        s(CardFace.four),
      ]);
      expect(straight.minBeatable, 1);
      expect(straight.unbeatable, 1);
      // Gap filler: 9 10 _ Q K A.
      final gap = solver.ofSlots([
        s(CardFace.nine),
        s(CardFace.ten),
        s(CardFace.queen),
        s(CardFace.king),
        s(CardFace.ace, CardColor.red),
        phoenix,
      ]);
      expect(gap.minBeatable, 0);
      // Full house with the Phoenix: 3 3 Ph + K K... and pair straights.
      final pairStraight = solver.ofSlots([
        s(CardFace.queen),
        s(CardFace.queen, CardColor.red),
        s(CardFace.king),
        phoenix,
        s(CardFace.ace),
        s(CardFace.ace, CardColor.red),
      ]);
      expect(pairStraight.minBeatable, 0); // QQ K(Ph) AA, top ace
    });

    test('bombs count as unbeatable', () {
      final solver = ClaimSolver.fromUnseen(
        unseenRank: allUnseen(),
        phoenix: true,
        dragon: true,
      );
      final quad = solver.ofSlots([
        for (final color in _suits) s(CardFace.seven, color),
        s(CardFace.three),
      ]);
      expect(quad.minBeatable, 1);
      expect(quad.unbeatable, 1);
      expect(quad.claimable, isTrue);

      final flush = solver.ofSlots([
        for (final f in [
          CardFace.two,
          CardFace.three,
          CardFace.four,
          CardFace.five,
          CardFace.six,
        ])
          s(f, CardColor.red),
        s(CardFace.six),
        s(CardFace.nine),
      ]);
      // Red 2-6 straight flush + 6 + 9: two beatable singles left.
      expect(flush.minBeatable, 2);
      expect(flush.unbeatable, 1);
    });

    test('Dog and Dragon', () {
      final solver = ClaimSolver.fromUnseen(
        unseenRank: allUnseen(),
        phoenix: true,
        dragon: false,
      );
      final dogDragon = solver.ofSlots([dog, dragon]);
      expect(dogDragon.minBeatable, 1);
      expect(dogDragon.unbeatable, 1);
      expect(dogDragon.claimable, isTrue);
      expect(solver.ofSlots([dog, s(CardFace.three)]).minBeatable, 2);
      expect(solver.ofSlots(const []).minBeatable, 0);
    });

    test('Mah Jong straight', () {
      final solver = ClaimSolver.fromUnseen(
        unseenRank: unseen({7: 1}),
        phoenix: false,
        dragon: false,
      );
      // 1-5: beaten by nothing (no unseen straight); 1..5 + 9.
      final out = solver.ofSlots([
        mahJong,
        s(CardFace.two),
        s(CardFace.three),
        s(CardFace.four),
        s(CardFace.five),
      ]);
      expect(out.minBeatable, 0);
    });
  });

  test('matches a card-level brute force over generator leads', () {
    final rng = Random(11);
    final deck = <Card>[
      for (final color in _suits)
        for (final face in CardFace.values)
          if (faceRank(face) >= 2) Card(face, color),
      Card(CardFace.mahJong, CardColor.special),
      Card(CardFace.dog, CardColor.special),
      const Card.phoenix(-10),
      Card(CardFace.dragon, CardColor.special),
    ];
    var claimable = 0;
    var checked = 0;
    for (var trial = 0; trial < 1500; trial++) {
      deck.shuffle(rng);
      final n = 1 + rng.nextInt(14);
      final mine = deck.sublist(0, n);
      // A random part of the rest is unseen (spread over the others).
      final unseenCount = rng.nextInt(deck.length - n);
      final others = <String, List<Card>>{
        aiTestLeftId: [],
        aiTestPartnerId: [],
        aiTestRightId: [],
      };
      final ids = others.keys.toList();
      for (var i = 0; i < unseenCount; i++) {
        others[ids[i % 3]]!.add(deck[n + i]);
      }
      final k = CardKnowledge.fromSnapshot(
        fxSnapshot(mine: mine, others: others),
        aiTestSelfId,
      );
      final solver = ClaimSolver.of(k);
      final slots = mine.map(cardSlot).toList();
      final got = solver.ofSlots(slots);
      final (b, u) = referenceClaim(mine, k);
      // The capped score (lower-bound shortcut) gives the same features.
      final exact = List<double>.filled(3, 0);
      final capped = List<double>.filled(3, 0);
      got.writeTo(exact, 0);
      ClaimResult.writeScore(solver.scoreOfSlots(slots), capped, 0);
      expect(
        capped,
        exact,
        reason: 'capped features ${mine.map((x) => x.face.name).join(' ')}',
      );
      expect(
        (got.minBeatable, got.unbeatable),
        (b, u),
        reason: 'hand ${mine.map((x) => x.face.name).join(' ')}',
      );
      // Sub-hands after each lead, from the memo or searched, match a
      // fresh analysis of the remaining cards.
      final hand = solver.hand(slots);
      expect(hand.score, solver.scoreOfSlots(slots));
      final deckState = DeckState(
        TichuTurn(TurnType.empty, const []),
        CardFace.none,
      );
      for (final turn in generateLegalTurns(deckState, mine)) {
        final played = turn.cards.map(cardSlot).toSet();
        final remaining = [
          for (final x in slots)
            if (!played.contains(x)) x,
        ];
        final a = List<double>.filled(3, 0);
        final f = List<double>.filled(3, 0);
        ClaimResult.writeScore(solver.after(hand, turn.cards, remaining), a, 0);
        solver.ofSlots(remaining).writeTo(f, 0);
        expect(a, f, reason: 'after ${turn.cards.map((x) => x.face.name)}');
      }
      checked++;
      if (b <= 1) claimable++;
    }
    expect(checked, 1500);
    expect(claimable, greaterThan(100)); // the test covers both outcomes
  });
}
