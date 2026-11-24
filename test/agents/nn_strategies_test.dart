import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/nn/feature_encoder.dart';
import 'package:tichu/agents/nn/mlp.dart';
import 'package:tichu/agents/nn/nn_play_selection_strategy.dart';
import 'package:tichu/agents/nn/nn_tichu_call_strategy.dart';
import 'package:tichu/agents/play_selection_strategy.dart';
import 'package:tichu/agents/tichu_call_strategy.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'ai_test_fixtures.dart';

void main() {
  group('older play-net layouts', () {
    // Old layouts: a state prefix and the first 51 action features.
    for (final (size, state) in [
      (427, 373),
      (376, 322),
      (319, 268),
      (318, 267),
      (252, 201),
    ]) {
      test('$size inputs play exactly like the zero-widened net', () {
        final old = Mlp(layerSizes: [size, 16, 8, 1], seed: size);
        final wide = old.widenInputs(
          totalFeatureCount,
          (i) => i < state ? i : actionOffset + i - state,
        );
        expect(playNetLayout(size), (state: state, action: size - state));
        for (final simd in [false, true]) {
          final a = NnPlaySelectionStrategy(
            playerId: aiTestSelfId,
            network: old,
            simd: simd,
          );
          final b = NnPlaySelectionStrategy(
            playerId: aiTestSelfId,
            network: wide,
            simd: simd,
          );
          for (var k = 0; k < 20; k++) {
            final h = [
              for (var r = 0; r < 6; r++)
                Card(
                  CardFace.values[2 + (k * 5 + r * 3) % 13],
                  CardColor.values[(k + r) % 4],
                ),
            ];
            final ps = [
              for (final c in h) TichuTurn(TurnType.single, [c]),
            ];
            final snapshot = aiSnapshot(myHand: h);
            expect(
              a.selectTurnOrPass(snapshot, ps, snapshot.deck, h, canPass: true),
              b.selectTurnOrPass(snapshot, ps, snapshot.deck, h, canPass: true),
            );
          }
        }
      });
    }

    test('unknown input sizes are rejected', () {
      expect(
        () => NnPlaySelectionStrategy(
          playerId: aiTestSelfId,
          network: Mlp(layerSizes: [320, 1], seed: 1),
        ),
        throwsArgumentError,
      );
    });
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
