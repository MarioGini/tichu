import 'dart:typed_data';

import 'package:tichu/agents/nn/mlp.dart';
import 'package:tichu/agents/nn/wasm_mlp_kernel_stub.dart'
    if (dart.library.js_interop) 'package:tichu/agents/nn/wasm_mlp_kernel_web.dart'
    as impl;

/// The play net's scorer on the wasm SIMD kernel
/// (`assets/bots/mlp_kernel.wasm`, built from `web_kernel/mlp_kernel.c`):
/// float32 x4 like [MlpSimdPrefixScorer], which dart2js cannot run fast.
/// Null outside the web and in browsers without wasm SIMD.
Future<PrefixScorerFactory?> loadWasmScorer(Uint8List kernelBytes) =>
    impl.loadWasmScorer(kernelBytes);
