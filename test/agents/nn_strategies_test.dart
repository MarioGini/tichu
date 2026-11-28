import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/nn/belief_model.dart';
import 'package:tichu/agents/nn/feature_encoder.dart';
import 'package:tichu/agents/nn/mlp.dart';
import 'package:tichu/agents/nn/nn_play_selection_strategy.dart';
import 'package:tichu/agents/nn/nn_tichu_call_strategy.dart';
import 'package:tichu/agents/play_selection_strategy.dart';
import 'package:tichu/agents/tichu_call_strategy.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'ai_test_fixtures.dart';

void main() {
  group('belief inputs', () {
    final belief = BeliefModel(
      Mlp(layerSizes: [stateFeatureCount, 8, 56 * 3], seed: 9),
    );
    const withBelief =
        totalFeatureCount + NnPlaySelectionStrategy.beliefInputCount;
    test('a belief-input net needs the belief model, and vice versa', () {
      expect(
        () => NnPlaySelectionStrategy(
          playerId: aiTestSelfId,
          network: Mlp(layerSizes: [withBelief, 1], seed: 1),
        ),
        throwsArgumentError,
      );
      expect(
        () => NnPlaySelectionStrategy(
          playerId: aiTestSelfId,
          network: Mlp(layerSizes: [totalFeatureCount, 1], seed: 1),
          belief: belief,
        ),
        throwsArgumentError,
      );
    });
    test('the belief follows the state in the scored input', () {
      // A 599-input net scores through the state + belief prefix (the
      // zero-weight warm start's equivalence is tested in Python).
      final snap = aiSnapshot(
        myHand: [
          Card(CardFace.two, CardColor.red),
          Card(CardFace.king, CardColor.green),
        ],
        otherHands: const {},
      );
      final plays = [
        for (final c in snap.hands[aiTestSelfId]!)
          TichuTurn(TurnType.single, [c]),
      ];
      final strategy = NnPlaySelectionStrategy(
        playerId: aiTestSelfId,
        network: Mlp(layerSizes: [withBelief, 1], seed: 2),
        belief: belief,
      );
      final q = strategy.qValues(snap, plays);
      expect(q, hasLength(2));
      expect(q.every((v) => v.isFinite), isTrue);
      final p = belief.holderProbabilities(snap, aiTestSelfId);
      expect(p, hasLength(56));
    });
  });

  test('nets of other input sizes are rejected', () {
    // 376: the v8 layout, no longer supported.
    for (final size in [376, 320]) {
      expect(
        () => NnPlaySelectionStrategy(
          playerId: aiTestSelfId,
          network: Mlp(layerSizes: [size, 1], seed: 1),
        ),
        throwsArgumentError,
      );
    }
  });

  final hand = [
    Card(CardFace.two, CardColor.red),
    Card(CardFace.five, CardColor.blue),
    Card(CardFace.king, CardColor.green),
  ];
  final plays = [
    for (final c in hand) TichuTurn(TurnType.single, [c]),
  ];

  group('NnPlaySelectionStrategy as FullTurnPolicy', () {
    for (final seed in [1, 2, 3, 4, 5]) {
      test('returns a legal play, never pass when pass is illegal '
          '(seed $seed)', () {
        final strategy = NnPlaySelectionStrategy(
          playerId: aiTestSelfId,
          network: Mlp(layerSizes: [totalFeatureCount, 8, 1], seed: seed),
        );
        expect(strategy, isA<FullTurnPolicy>());
        final snapshot = aiSnapshot(myHand: hand);
        final selected = strategy.selectTurnOrPass(
          snapshot,
          plays,
          snapshot.deck,
          hand,
          canPass: false,
        );
        expect(selected, isNotNull);
        expect(plays, contains(selected));
      });
    }

    test('passes when no plays are legal and pass is allowed', () {
      final strategy = NnPlaySelectionStrategy(
        playerId: aiTestSelfId,
        network: Mlp(layerSizes: [totalFeatureCount, 1], seed: 1),
      );
      final snapshot = aiSnapshot(myHand: hand);
      expect(
        strategy.selectTurnOrPass(
          snapshot,
          const [],
          snapshot.deck,
          hand,
          canPass: true,
        ),
        isNull,
      );
    });
  });

  group('NnTichuCallStrategy', () {
    test('rejects networks with the wrong input size', () {
      expect(
        () => NnTichuCallStrategy(
          tichuNetwork: Mlp(layerSizes: [totalFeatureCount, 1], seed: 1),
        ),
        throwsArgumentError,
      );
    });

    test('falls back to the heuristic when a network is missing', () async {
      final strategy = NnTichuCallStrategy(
        tichuNetwork: Mlp(layerSizes: [callNetInputSize, 1], seed: 1),
      );
      final snapshot = aiSnapshot(myHand: hand);
      expect(
        await strategy.shouldCallGrandTichu(snapshot, aiTestSelfId),
        await const DefaultTichuCallStrategy().shouldCallGrandTichu(
          snapshot,
          aiTestSelfId,
        ),
      );
    });

    test('calls iff Q(s, call) - Q(s, no call) exceeds the margin', () async {
      final net = Mlp(layerSizes: [callNetInputSize, 4, 1], seed: 7);
      final snapshot = aiSnapshot(myHand: hand);
      final adv = NnTichuCallStrategy.callAdvantage(
        net,
        100,
        snapshot,
        aiTestSelfId,
      );
      final below = NnTichuCallStrategy(tichuNetwork: net, margin: adv - 1);
      final above = NnTichuCallStrategy(tichuNetwork: net, margin: adv + 1);
      expect(await below.shouldCallTichu(snapshot, aiTestSelfId), isTrue);
      expect(await above.shouldCallTichu(snapshot, aiTestSelfId), isFalse);
    });
  });
}
