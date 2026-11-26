import 'dart:typed_data';

import 'package:tichu/agents/nn/mlp.dart';

/// Native builds score with [MlpSimdPrefixScorer].
Future<Uint8List?> fetchWasmKernel() async => null;

Future<PrefixScorerFactory> loadWasmScorer(Uint8List kernel) =>
    throw UnsupportedError('The wasm kernel runs only on the web.');
