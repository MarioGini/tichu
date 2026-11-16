import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/nn/mlp.dart';

void main() {
  group('MlpPrefixScorer', () {
    for (final sizes in [
      [30, 1],
      [30, 16, 1],
      [30, 24, 12, 6, 1],
    ]) {
      test('matches the dense forward pass for layers $sizes', () {
        final net = Mlp(layerSizes: sizes, seed: 11);
        final rng = Random(5);
        const prefixLength = 18;
        final scorer = net.prefixScorer(prefixLength);
        for (var decision = 0; decision < 20; decision++) {
          // Sparse inputs with zeros and negatives, like the real features.
          double value() =>
              rng.nextDouble() < 0.6 ? 0.0 : rng.nextDouble() * 2 - 1;
          final prefix = [for (var i = 0; i < prefixLength; i++) value()];
          scorer.setPrefix(prefix);
          for (var action = 0; action < 5; action++) {
            final suffix = Float64List.fromList([
              for (var i = prefixLength; i < sizes.first; i++) value(),
            ]);
            final dense = net.predictBuffer(
              Float64List.fromList([...prefix, ...suffix]),
            );
            expect(scorer.score(suffix), closeTo(dense, 1e-9));
          }
        }
      });
    }

    test('rejects a prefix longer than the input', () {
      expect(
        () => Mlp(layerSizes: [4, 1], seed: 1).prefixScorer(5),
        throwsArgumentError,
      );
    });
  });
}
