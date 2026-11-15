import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/nn/feature_encoder.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'ai_test_fixtures.dart';

Card c(final CardFace face, [final CardColor color = CardColor.black]) =>
    Card(face, color);

GameSnapshot _snapshot({
  required final List<Card> mine,
  required final Map<String, List<Card>> others,
  final DeckState? deck,
  final int trickPoints = 0,
  final List<String> finishOrder = const [],
  final Map<String, TichuCall> calls = const {},
  final Map<String, List<SchupfReceipt>> receipts = const {},
}) {
  final base = aiSnapshot(
    myHand: mine,
    otherHands: others,
    deck: deck,
    tichuCalls: calls,
    schupfReceipts: receipts,
  );
  return GameSnapshot(
    gameId: base.gameId,
    players: base.players,
    hands: base.hands,
    deck: base.deck,
    trickPoints: trickPoints,
    activeWish: base.activeWish,
    currentPlayerId: base.currentPlayerId,
    consecutivePasses: base.consecutivePasses,
    lastPlayedBy: base.lastPlayedBy,
    lastPlayedTurn: base.lastPlayedTurn,
    lastDragonGiveBy: null,
    lastDragonGiveTo: null,
    pendingDragonGiveBy: null,
    pendingDragonGiveTargets: const [],
    pendingOpponentPlayerId: null,
    pendingOpponentCards: const [],
    pendingOpponentPass: false,
    scoreState: base.scoreState.copyWith(finishOrder: finishOrder),
    opponentAwaitingConfirmation: false,
    phase: GamePhase.play,
    grandTichuDecisions: const {},
    schupfCompletedPlayers: const [],
    schupfReceipts: base.schupfReceipts,
  );
}

int _slot(final String group, final int i) => switch (group) {
  'hand' => handOffset + i,
  'played' => playedOffset + i,
  'unseen' => unseenOffset + i,
  'trick' => trickOffset + i,
  'seats' => seatsOffset + i,
  'self' => selfOffset + i,
  _ => throw ArgumentError(group),
};

void main() {
  test('vector sizes', () {
    final snap = _snapshot(
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
    final snap = _snapshot(
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
    expect(f[_slot('hand', redAce)], 1.0);
    expect(f[_slot('hand', 55)], 1.0); // dragon
    expect(f[_slot('played', redAce)], 0.0);
    expect(f[_slot('played', blueAce)], 0.0); // still in left's hand
    // Black and green aces are out of play.
    expect(f[_slot('played', cardSlot(c(CardFace.ace)))], 1.0);
    // Unseen aces: only the blue one (1/4); phoenix unseen; dragon mine.
    expect(f[_slot('unseen', 12)], 0.25);
    expect(f[_slot('unseen', 15)], 1.0);
    expect(f[_slot('unseen', 16)], 0.0);
  });

  test('seat features distinguish partner from opponents', () {
    final snap = _snapshot(
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
    expect(f[_slot('seats', 0)], 1 / 14); // left card count
    expect(f[_slot('seats', 1)], 1.0); // left has one card
    expect(f[_slot('seats', 9)], 2 / 14); // partner card count
    expect(f[_slot('seats', 9 + 1)], 0.0);
    expect(f[_slot('seats', 18 + 3)], 1.0); // right finished
    expect(f[_slot('seats', 18 + 4)], 1.0); // right finished first
    expect(f[_slot('seats', 18 + 5)], 1.0); // right called tichu
    expect(f[_slot('self', 7)], 1.0); // opponent team finished first
  });

  test('action: hand-after shape and bomb breaking', () {
    final mine = [
      c(CardFace.seven),
      c(CardFace.seven, CardColor.green),
      c(CardFace.seven, CardColor.red),
      c(CardFace.seven, CardColor.blue),
      c(CardFace.three),
    ];
    final snap = _snapshot(
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
    final snap = _snapshot(
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
    expect(f[_slot('trick', 1)], 1.0); // single on table
    expect(f[_slot('trick', 10)], 0.2); // 10 points
    expect(f[_slot('trick', 13)], 1.0); // partner is winning

    final ace = enc.actionFeatures(TichuTurn(TurnType.single, [mine[0]]));
    expect(ace[18], 1.0); // overtakes partner
    expect(ace[21], 1.0); // nothing unseen beats it (no dragon/phoenix out)
    final jack = enc.actionFeatures(TichuTurn(TurnType.single, [mine[1]]));
    expect(jack[21], 0.0); // king of left beats it
  });

  test('known schupf cards still held', () {
    final passed = c(CardFace.dog, CardColor.special);
    final snap = _snapshot(
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
    expect(f[_slot('seats', 8)], 1 / 3);
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
      snapshot: _snapshot(mine: mine, others: others),
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
      final snap = _snapshot(
        mine: [dragon],
        others: {
          aiTestLeftId: quadNines,
          aiTestPartnerId: [c(CardFace.two)],
          aiTestRightId: [c(CardFace.three)],
        },
      );
      final enc = FeatureEncoder(snapshot: snap, playerId: aiTestSelfId);
      expect(enc.actionFeatures(TichuTurn(TurnType.single, [dragon]))[21], 1.0);
      expect(enc.stateFeatures[_slot('self', 14)], 1.0); // bomb possible
    });
  });
}
