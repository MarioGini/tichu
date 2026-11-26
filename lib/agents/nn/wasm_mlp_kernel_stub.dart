import 'dart:typed_data';

import 'package:tichu/agents/nn/mlp.dart';

/// Native builds score with [MlpSimdPrefixScorer].
Future<PrefixScorerFactory?> loadWasmScorer(Uint8List kernelBytes) async =>
    null;
