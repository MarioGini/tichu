import 'dart:js_interop';
import 'dart:typed_data';

import 'package:tichu/agents/nn/mlp.dart';

@JS('WebAssembly.validate')
external bool _validate(JSUint8Array bytes);

@JS('WebAssembly.instantiate')
external JSPromise<_Instantiated> _instantiate(
  JSUint8Array bytes,
  JSObject imports,
);

extension type _Instantiated(JSObject _) implements JSObject {
  external _Instance get instance;
}

extension type _Instance(JSObject _) implements JSObject {
  external _Exports get exports;
}

extension type _Memory(JSObject _) implements JSObject {
  external JSArrayBuffer get buffer;
}

extension type _Exports(JSObject _) implements JSObject {
  external _Memory get memory;
  @JS('net_new')
  external int netNew(
    int layers,
    int s0,
    int s1,
    int s2,
    int s3,
    int s4,
    int s5,
    int s6,
    int s7,
    int s8,
  );
  @JS('net_weights')
  external int netWeights(int net, int layer);
  @JS('net_bias')
  external int netBias(int net, int layer);
  @JS('net_input')
  external int netInput(int net);
  @JS('net_set_prefix')
  external void netSetPrefix(int net, int prefixLength);
  @JS('net_score')
  external double netScore(int net, int prefixLength, int suffixLength);
}

Future<PrefixScorerFactory?> loadWasmScorer(Uint8List kernelBytes) async {
  final bytes = kernelBytes.toJS;
  // False where the browser lacks wasm SIMD: the Dart scorer is used.
  if (!_validate(bytes)) return null;
  final instantiated = await _instantiate(bytes, JSObject()).toDart;
  final kernel = _Kernel(instantiated.instance.exports);
  return kernel.scorer;
}

/// One wasm instance; one kernel net per [Mlp] (the bots built from a
/// config share their nets), shared by all scorers of that net.
class _Kernel {
  _Kernel(this._exports);

  final _Exports _exports;
  final Map<Mlp, _KernelNet> _nets = Map.identity();

  /// Float view of the wasm memory; replaced when a new net grows it.
  late Float32List heap = _view();

  Float32List _view() => _exports.memory.buffer.toDart.asFloat32List();

  PrefixScorer scorer(Mlp net, int prefixLength) =>
      _WasmPrefixScorer(_nets[net] ??= _load(net), prefixLength);

  _KernelNet _load(Mlp net) {
    final sizes = [...net.layerSizes, ...List.filled(9, 0)];
    final id = _exports.netNew(
      net.numLayers,
      sizes[0],
      sizes[1],
      sizes[2],
      sizes[3],
      sizes[4],
      sizes[5],
      sizes[6],
      sizes[7],
      sizes[8],
    );
    // net_new may have grown the memory (a new buffer).
    heap = _view();
    for (var l = 0; l < net.numLayers; l++) {
      final w = net.simdWeightLayout(l);
      heap.setAll(_exports.netWeights(id, l) ~/ 4, w);
      final b = net.simdBiasLayout(l);
      heap.setAll(_exports.netBias(id, l) ~/ 4, b);
    }
    return _KernelNet(this, id, _exports.netInput(id) ~/ 4, net.inputSize);
  }
}

class _KernelNet {
  _KernelNet(this.kernel, this.id, this.input, this.inputSize);

  final _Kernel kernel;
  final int id;

  /// Index of the input buffer in [_Kernel.heap].
  final int input;
  final int inputSize;

  /// The scorer whose prefix the kernel holds.
  _WasmPrefixScorer? prefixOwner;
}

/// [PrefixScorer] on the kernel. Scorers of one net share the kernel's
/// prefix buffer: each keeps its prefix and sets it again when another
/// scorer of the net set its own in between.
class _WasmPrefixScorer implements PrefixScorer {
  _WasmPrefixScorer(this._net, this.prefixLength)
    : _prefix = Float32List(prefixLength);

  final _KernelNet _net;
  final int prefixLength;
  final Float32List _prefix;

  @override
  void setPrefix(List<double> prefix) {
    for (var i = 0; i < prefixLength; i++) {
      _prefix[i] = prefix[i];
    }
    _load();
  }

  void _load() {
    final net = _net;
    net.kernel.heap.setAll(net.input, _prefix);
    net.kernel._exports.netSetPrefix(net.id, prefixLength);
    net.prefixOwner = this;
  }

  @override
  double score(List<double> suffix, [int offset = 0]) {
    final net = _net;
    if (!identical(net.prefixOwner, this)) _load();
    final heap = net.kernel.heap;
    final n = net.inputSize - prefixLength;
    final base = net.input;
    for (var i = 0; i < n; i++) {
      heap[base + i] = suffix[offset + i];
    }
    return net.kernel._exports.netScore(net.id, prefixLength, n);
  }
}
