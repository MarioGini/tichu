import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/nn/feature_encoder.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/round_log.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'ai_test_fixtures.dart';

import 'feature_encoder_fixtures.dart';

void main() {
  test('vector sizes', () {
    final snap = fxSnapshot(
      mine: [c(CardFace.two)],
      others: {
        aiTestLeftId: [c(CardFace.three)],
        aiTestPartnerId: [c(CardFace.four)],
        aiTestRightId: [c(CardFace.five)],
      },
    );
    final enc = FeatureEncoder(snapshot: snap, playerId: aiTestSelfId);
    expect(enc.stateFeatures.length, stateFeatureCount);
    expect(
      enc.actionFeatures(TichuTurn(TurnType.single, [c(CardFace.two)])).length,
      actionFeatureCount,
    );
  });

  test('hand / played / unseen bitmaps are complementary', () {
    final snap = fxSnapshot(
      mine: [
        c(CardFace.ace, CardColor.red),
        c(CardFace.dragon, CardColor.special),
      ],
      others: {
        aiTestLeftId: [c(CardFace.ace, CardColor.blue)],
        aiTestPartnerId: [c(CardFace.phoenix, CardColor.special)],
        aiTestRightId: [c(CardFace.two, CardColor.green)],
      },
    );
    final f = encodeStateFeatures(snapshot: snap, playerId: aiTestSelfId);
    final redAce = cardSlot(c(CardFace.ace, CardColor.red));
    final blueAce = cardSlot(c(CardFace.ace, CardColor.blue));
    expect(f[slot('hand', redAce)], 1.0);
    expect(f[slot('hand', 55)], 1.0); // dragon
    expect(f[slot('played', redAce)], 0.0);
    expect(f[slot('played', blueAce)], 0.0); // still in left's hand
    // Black and green aces are out of play.
    expect(f[slot('played', cardSlot(c(CardFace.ace)))], 1.0);
    // Unseen aces: only the blue one (1/4); phoenix unseen; dragon mine.
    expect(f[slot('unseen', 12)], 0.25);
    expect(f[slot('unseen', 15)], 1.0);
    expect(f[slot('unseen', 16)], 0.0);
  });

  test('seat features distinguish partner from opponents', () {
    final snap = fxSnapshot(
      mine: List.generate(5, (final i) => c(CardFace.values[2 + i])),
      others: {
        aiTestLeftId: [c(CardFace.king, CardColor.red)],
        aiTestPartnerId: [
          c(CardFace.queen, CardColor.red),
          c(CardFace.queen, CardColor.blue),
        ],
        aiTestRightId: const [],
      },
      finishOrder: const [aiTestRightId],
      calls: const {aiTestRightId: TichuCall.tichu},
    );
    final f = encodeStateFeatures(snapshot: snap, playerId: aiTestSelfId);
    expect(f[slot('seats', 0)], 1 / 14); // left card count
    expect(f[slot('seats', 1)], 1.0); // left has one card
    expect(f[slot('seats', 9)], 2 / 14); // partner card count
    expect(f[slot('seats', 9 + 1)], 0.0);
    expect(f[slot('seats', 18 + 3)], 1.0); // right finished
    expect(f[slot('seats', 18 + 4)], 1.0); // right finished first
    expect(f[slot('seats', 18 + 5)], 1.0); // right called tichu
    expect(f[slot('self', 7)], 1.0); // opponent team finished first
  });

  test('action: hand-after shape and bomb breaking', () {
    final mine = [
      c(CardFace.seven),
      c(CardFace.seven, CardColor.green),
      c(CardFace.seven, CardColor.red),
      c(CardFace.seven, CardColor.blue),
      c(CardFace.three),
    ];
    final snap = fxSnapshot(
      mine: mine,
      others: {
        aiTestLeftId: [c(CardFace.ace, CardColor.red)],
        aiTestPartnerId: [c(CardFace.two, CardColor.red)],
        aiTestRightId: [c(CardFace.four, CardColor.red)],
      },
    );
    final enc = FeatureEncoder(snapshot: snap, playerId: aiTestSelfId);

    final pairOfSevens = enc.actionFeatures(
      TichuTurn(TurnType.pair, [mine[0], mine[1]]),
    );
    expect(pairOfSevens[2], 1.0); // type_pair
    expect(pairOfSevens[22], 1.0); // breaks_bomb
    expect(pairOfSevens[23 + 5], 0.5); // two sevens in histogram
    expect(pairOfSevens[40], 3 / 14); // three cards left

    final three = enc.actionFeatures(TichuTurn(TurnType.single, [mine[4]]));
    expect(three[22], 0.0); // bomb intact
    expect(three[21], 0.0); // ace of left beats a three
    expect(three[41 + 3], 0.5); // one bomb remains (bombs / 2)

    final bomb = enc.actionFeatures(
      TichuTurn(TurnType.bomb, mine.sublist(0, 4)),
    );
    expect(bomb[7], 1.0);
    expect(bomb[22], 0.0);

    final pass = enc.actionFeatures(
      TichuTurn(TurnType.none, const []),
      isPass: true,
    );
    expect(pass[0], 1.0);
    expect(pass[40], 5 / 14);
  });

  test('action: unbeatable single and overtaking partner', () {
    final deck = DeckState(
      TichuTurn(TurnType.single, [c(CardFace.ten, CardColor.green)]),
      CardFace.none,
    )..currentWinner = aiTestPartnerId;
    final mine = [c(CardFace.ace, CardColor.red), c(CardFace.jack)];
    final snap = fxSnapshot(
      mine: mine,
      deck: deck,
      trickPoints: 10,
      others: {
        aiTestLeftId: [c(CardFace.king, CardColor.red)],
        aiTestPartnerId: [c(CardFace.two, CardColor.red)],
        aiTestRightId: [c(CardFace.four, CardColor.red)],
      },
    );
    final enc = FeatureEncoder(snapshot: snap, playerId: aiTestSelfId);
    final f = enc.stateFeatures;
    expect(f[slot('trick', 1)], 1.0); // single on table
    expect(f[slot('trick', 10)], 0.2); // 10 points
    expect(f[slot('trick', 13)], 1.0); // partner is winning

    final ace = enc.actionFeatures(TichuTurn(TurnType.single, [mine[0]]));
    expect(ace[18], 1.0); // overtakes partner
    expect(ace[21], 1.0); // nothing unseen beats it (no dragon/phoenix out)
    final jack = enc.actionFeatures(TichuTurn(TurnType.single, [mine[1]]));
    expect(jack[21], 0.0); // king of left beats it
  });

  test('known schupf cards still held', () {
    final passed = c(CardFace.dog, CardColor.special);
    final snap = fxSnapshot(
      mine: [c(CardFace.two)],
      others: {
        aiTestLeftId: [passed, c(CardFace.three)],
        aiTestPartnerId: [c(CardFace.four)],
        aiTestRightId: [c(CardFace.five)],
      },
      receipts: {
        aiTestLeftId: [
          SchupfReceipt(
            card: passed,
            fromPlayerId: aiTestSelfId,
            direction: SchupfDirection.values.first,
          ),
        ],
      },
    );
    final f = encodeStateFeatures(snapshot: snap, playerId: aiTestSelfId);
    expect(f[slot('seats', 8)], 1 / 3);
  });

  test('HandShape detects straights with phoenix and full houses', () {
    List<int> slots(final List<Card> cards) => [
      for (final card in cards) cardSlot(card),
    ];
    final straight = HandShape.fromSlots(
      slots([
        c(CardFace.three),
        c(CardFace.four),
        c(CardFace.six),
        c(CardFace.seven),
        c(CardFace.phoenix, CardColor.special),
      ]),
    );
    expect(straight.hasStraight, isTrue);
    expect(straight.longestRun, 5);
    expect(straight.estPlays, 1);

    final fullHouse = HandShape.fromSlots(
      slots([
        c(CardFace.nine),
        c(CardFace.nine, CardColor.red),
        c(CardFace.nine, CardColor.blue),
        c(CardFace.king),
        c(CardFace.king, CardColor.red),
      ]),
    );
    expect(fullHouse.triplets, 1);
    expect(fullHouse.pairs, 1);
    expect(fullHouse.estPlays, 1);
  });

  group('deterministic beatability', () {
    FeatureEncoder encoderFor(
      final List<Card> mine,
      final Map<String, List<Card>> others,
    ) => FeatureEncoder(
      snapshot: fxSnapshot(mine: mine, others: others),
      playerId: aiTestSelfId,
    );

    test('single ace is beatable while dragon or phoenix is out', () {
      final ace = c(CardFace.ace, CardColor.red);
      final withDragon = encoderFor(
        [ace],
        {
          aiTestLeftId: [c(CardFace.dragon, CardColor.special)],
          aiTestPartnerId: [c(CardFace.two)],
          aiTestRightId: [c(CardFace.three)],
        },
      ).actionFeatures(TichuTurn(TurnType.single, [ace]));
      expect(withDragon[21], 0.0);

      final withPhoenix = encoderFor(
        [ace],
        {
          aiTestLeftId: [c(CardFace.phoenix, CardColor.special)],
          aiTestPartnerId: [c(CardFace.two)],
          aiTestRightId: [c(CardFace.three)],
        },
      ).actionFeatures(TichuTurn(TurnType.single, [ace]));
      expect(withPhoenix[21], 0.0);
    });

    test('pair of kings: beaten by two unseen aces or ace + phoenix', () {
      final kings = [c(CardFace.king), c(CardFace.king, CardColor.red)];
      final play = TichuTurn(TurnType.pair, kings);

      final oneAce = encoderFor(kings, {
        aiTestLeftId: [c(CardFace.ace)],
        aiTestPartnerId: [c(CardFace.two)],
        aiTestRightId: [c(CardFace.three)],
      }).actionFeatures(play);
      expect(oneAce[21], 1.0);

      final acePlusPhoenix = encoderFor(kings, {
        aiTestLeftId: [c(CardFace.ace)],
        aiTestPartnerId: [c(CardFace.phoenix, CardColor.special)],
        aiTestRightId: [c(CardFace.three)],
      }).actionFeatures(play);
      expect(acePlusPhoenix[21], 0.0);
    });

    test('bombs are ignored: dragon stays unbeatable with a bomb out', () {
      final dragon = c(CardFace.dragon, CardColor.special);
      final quadNines = [
        for (final color in [
          CardColor.black,
          CardColor.green,
          CardColor.red,
          CardColor.blue,
        ])
          c(CardFace.nine, color),
      ];
      final snap = fxSnapshot(
        mine: [dragon],
        others: {
          aiTestLeftId: quadNines,
          aiTestPartnerId: [c(CardFace.two)],
          aiTestRightId: [c(CardFace.three)],
        },
      );
      final enc = FeatureEncoder(snapshot: snap, playerId: aiTestSelfId);
      expect(enc.actionFeatures(TichuTurn(TurnType.single, [dragon]))[21], 1.0);
      expect(enc.stateFeatures[slot('self', 14)], 1.0); // bomb possible
    });
  });

  test('history: cards played and passes on opponents per player', () {
    RoundLogEntry play(final String id, final List<Card> cards) =>
        RoundLogEntry(
          playerId: id,
          cards: cards,
          trickType: TurnType.empty,
          trickValue: 0,
          trickWinner: '',
        );
    RoundLogEntry pass(
      final String id,
      final TurnType type,
      final double value,
      final String winner,
    ) => RoundLogEntry(
      playerId: id,
      cards: const [],
      trickType: type,
      trickValue: value,
      trickWinner: winner,
    );
    final snap = fxSnapshot(
      mine: [c(CardFace.two)],
      others: {
        aiTestLeftId: [c(CardFace.three)],
        aiTestPartnerId: [c(CardFace.four)],
        aiTestRightId: [c(CardFace.five)],
      },
      roundLog: [
        play(aiTestLeftId, [c(CardFace.king), c(CardFace.king, CardColor.red)]),
        play(aiTestLeftId, [c(CardFace.dragon, CardColor.special)]),
        // Left passes on my (an opponent's) queen and on a pair of nines.
        pass(aiTestLeftId, TurnType.single, 12, aiTestSelfId),
        pass(aiTestLeftId, TurnType.single, 10, aiTestRightId),
        pass(aiTestLeftId, TurnType.pair, 9, aiTestSelfId),
        // Partner passes on left's ace: an opponent's trick.
        pass(aiTestPartnerId, TurnType.single, 14, aiTestLeftId),
        // Right passes on left's (its partner's) trick: no evidence.
        pass(aiTestRightId, TurnType.single, 3, aiTestLeftId),
      ],
    );
    final f = encodeStateFeatures(snapshot: snap, playerId: aiTestSelfId);
    // Left (block 0): two kings, the dragon.
    expect(f[slot('history', 11)], 0.5);
    expect(f[slot('history', 16)], 1.0);
    expect(f[slot('history', 17)], 1.0);
    expect(f[slot('history', 18)], closeTo(12 / 15, 1e-9));
    expect(f[slot('history', 19)], 1.0);
    expect(f[slot('history', 20)], closeTo(9 / 15, 1e-9));
    expect(f[slot('history', 21)], closeTo(2 / 5, 1e-9));
    // Partner (block 1): passed on an ace.
    expect(f[slot('history', 22 + 18)], closeTo(14 / 15, 1e-9));
    // Right (block 2): its partner's trick is no evidence.
    expect(f[slot('history', 44 + 17)], 0.0);
    expect(f[slot('history', 44 + 21)], 0.0);
  });
}
