import 'dart:typed_data';

import 'package:tichu/agents/nn/mlp.dart';
import 'package:tichu/agents/nn/wasm_mlp_kernel_stub.dart'
    if (dart.library.js_interop) 'package:tichu/agents/nn/wasm_mlp_kernel_web.dart'
    as impl;

/// The play net's wasm SIMD kernel as the web app serves it
/// (`web/mlp_kernel_relaxed.wasm`, else `web/mlp_kernel.wasm`; built from
/// `web_kernel/mlp_kernel.c` by `tool/build_web.sh`): the first build this
/// browser can run. Null natively, when the files were not built, or in
/// browsers without wasm SIMD (the bots then score in Dart).
Future<Uint8List?> fetchWasmKernel() => impl.fetchWasmKernel();

/// The play net's scorer on [kernel] (bytes from [fetchWasmKernel]):
/// float32 x4 like [MlpSimdPrefixScorer], which dart2js cannot run fast.
Future<PrefixScorerFactory> loadWasmScorer(Uint8List kernel) =>
    impl.loadWasmScorer(kernel);
