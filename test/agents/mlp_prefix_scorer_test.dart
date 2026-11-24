import 'dart:convert';
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
        final simd = net.simdPrefixScorer(prefixLength);
        for (var decision = 0; decision < 20; decision++) {
          // Sparse inputs with zeros and negatives, like the real features.
          double value() =>
              rng.nextDouble() < 0.6 ? 0.0 : rng.nextDouble() * 2 - 1;
          final prefix = [for (var i = 0; i < prefixLength; i++) value()];
          scorer.setPrefix(prefix);
          simd.setPrefix(prefix);
          for (var action = 0; action < 5; action++) {
            final suffix = Float64List.fromList([
              for (var i = prefixLength; i < sizes.first; i++) value(),
            ]);
            final dense = net.predictBuffer(
              Float64List.fromList([...prefix, ...suffix]),
            );
            expect(scorer.score(suffix), closeTo(dense, 1e-9));
            // The float32 SIMD scorer agrees up to single precision.
            expect(simd.score(suffix), closeTo(dense, 1e-4));
          }
        }
      });
    }

    // The blocked SIMD kernel must give exactly the float32 result of adding
    // one input at a time in increasing order (rollout labels depend on it).
    test('SIMD scorer is bit-exact to sequential float32 sums', () {
      const sizes = [40, 36, 20, 9, 1];
      final rng = Random(9);
      final weights = [
        for (var l = 1; l < sizes.length; l++)
          Float32List.fromList([
            for (var k = 0; k < sizes[l] * sizes[l - 1]; k++)
              rng.nextDouble() - 0.5,
          ]),
      ];
      final biases = [
        for (var l = 1; l < sizes.length; l++)
          Float32List.fromList([
            for (var k = 0; k < sizes[l]; k++) rng.nextDouble() * 0.2 - 0.1,
          ]),
      ];
      final (net, _, _) = Mlp.fromSafetensorsBytes(
        _safetensors(sizes, weights, biases),
      );
      const prefixLength = 25;
      final simd = net.simdPrefixScorer(prefixLength);
      final f = Float32List(1); // rounds to float32 on store
      double r(double x) => (f..[0] = x)[0];
      for (var decision = 0; decision < 30; decision++) {
        double value() =>
            rng.nextDouble() < 0.6 ? 0.0 : rng.nextDouble() * 2 - 1;
        final input = [for (var i = 0; i < sizes.first; i++) value()];
        simd.setPrefix(Float64List.fromList(input.sublist(0, prefixLength)));
        final got = simd.score(
          Float64List.fromList(input.sublist(prefixLength)),
        );
        // Reference: prefix first, then suffix, each in input order.
        var act = input;
        for (var l = 0; l < weights.length; l++) {
          final inLen = sizes[l];
          final out = <double>[];
          for (var j = 0; j < sizes[l + 1]; j++) {
            var sum = r(biases[l][j]);
            for (var i = 0; i < inLen; i++) {
              final x = act[i];
              if (l == 0 ? x == 0 : x <= 0) continue;
              sum = r(sum + r(weights[l][j * inLen + i] * r(x)));
            }
            out.add(sum);
          }
          act = out;
        }
        expect(got, act.first);
      }
    });

    test('rejects a prefix longer than the input', () {
      expect(
        () => Mlp(layerSizes: [4, 1], seed: 1).prefixScorer(5),
        throwsArgumentError,
      );
    });
  });
}

/// A safetensors file of an MLP with the given float32 weights (row-major
/// (out, in)) and biases, as `rl/qnet.py` exports it.
Uint8List _safetensors(
  List<int> sizes,
  List<Float32List> weights,
  List<Float32List> biases,
) {
  final header = <String, Object>{
    '__metadata__': {'layer_sizes': jsonEncode(sizes)},
  };
  final data = BytesBuilder();
  for (var l = 0; l < weights.length; l++) {
    for (final (name, t, shape) in [
      ('weight', weights[l], [sizes[l + 1], sizes[l]]),
      ('bias', biases[l], [sizes[l + 1]]),
    ]) {
      final start = data.length;
      data.add(t.buffer.asUint8List());
      header['layer.$l.$name'] = {
        'dtype': 'F32',
        'shape': shape,
        'data_offsets': [start, data.length],
      };
    }
  }
  final json = utf8.encode(jsonEncode(header));
  final len = ByteData(8)..setUint64(0, json.length, Endian.little);
  return (BytesBuilder()
        ..add(len.buffer.asUint8List())
        ..add(json)
        ..add(data.takeBytes()))
      .takeBytes();
}
