import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// High-performance MLP for inference-only Q-value estimation.
///
/// Uses [Float64List] (typed arrays backed by contiguous memory) for all
/// weight storage and activations.  The Dart VM can apply SIMD vectorisation
/// to tight loops over typed data, giving ~2-4× speedup over generic
/// `List<double>` for the matrix-vector multiplies in forward().
///
/// Weight layout per layer: a single [Float64List] of length
/// `outSize × inSize`, stored **row-major** (neuron j's weights are
/// contiguous at offset `j * inSize`).  This matches how a CPU prefetcher
/// reads the inner dot-product loop.
///
/// Weights are loaded from safetensors files produced by Python/PyTorch.
/// Training is done exclusively in Python.
class Mlp {
  /// Flattened weight matrices per layer.  `_weights[l]` has length
  /// `layerSizes[l+1] * layerSizes[l]`.
  final List<Float64List> _weights;

  /// Bias vectors per layer.
  final List<Float64List> _biases;

  /// Layer sizes: [input, hidden1, …, output].
  final List<int> layerSizes;

  /// Pre-allocated activation buffers (one per layer output) to avoid
  /// allocation during forward().
  final List<Float64List> _buffers;

  // ── Random init (for tests) ─────────────────────────────────────────────

  factory Mlp({required List<int> layerSizes, int? seed}) {
    if (layerSizes.length < 2) {
      throw ArgumentError('Need at least input and output layer sizes.');
    }

    final rng = seed != null ? Random(seed) : Random();
    final weights = <Float64List>[];
    final biases = <Float64List>[];

    for (var l = 1; l < layerSizes.length; l++) {
      final fanIn = layerSizes[l - 1];
      final fanOut = layerSizes[l];
      final stddev = sqrt(2.0 / (fanIn + fanOut));

      final flat = Float64List(fanOut * fanIn);
      for (var k = 0; k < flat.length; k++) {
        flat[k] = _gaussian(rng) * stddev;
      }
      weights.add(flat);
      biases.add(Float64List(fanOut)); // zeros
    }

    return Mlp._(weights: weights, biases: biases, layerSizes: layerSizes);
  }

  Mlp._({
    required this._weights,
    required this._biases,
    required List<int> layerSizes,
  }) : // A typed copy: the sizes come from `jsonDecode(...).cast<int>()`,
       // whose every read goes through a cast wrapper (5 % of a search).
       layerSizes = Int32List.fromList(layerSizes),
       _buffers = [
         for (var l = 1; l < layerSizes.length; l++) Float64List(layerSizes[l]),
       ];

  int get inputSize => layerSizes.first;
  int get numLayers => _weights.length;

  // ── Inference ───────────────────────────────────────────────────────────

  /// Forward pass into pre-allocated [_buffers].  Returns the output buffer.
  ///
  /// The input is a [Float64List] so the hot inner loop can use typed
  /// indexing for the first layer (subsequent layers already use the
  /// pre-allocated typed buffers). Callers that already have a typed input
  /// (e.g. via [predictBuffer]) avoid an allocation/copy.
  Float64List _forwardTyped(Float64List input) {
    var inBuf = input;
    var inLen = input.length;

    for (var l = 0; l < numLayers; l++) {
      final w = _weights[l];
      final b = _biases[l];
      final outLen = b.length;
      final out = _buffers[l];
      final isHidden = l < numLayers - 1;

      for (var j = 0; j < outLen; j++) {
        var sum = b[j];
        final base = j * inLen;
        for (var i = 0; i < inLen; i++) {
          sum += w[base + i] * inBuf[i];
        }
        out[j] = isHidden && sum < 0 ? 0.0 : sum;
      }

      inBuf = out;
      inLen = outLen;
    }

    return _buffers.last;
  }

  /// Compute Q-value for a single state-action pair (output size == 1).
  double predict(List<double> input) {
    final typed = input is Float64List ? input : Float64List.fromList(input);
    return _forwardTyped(typed)[0];
  }

  /// Every output unit (for nets with several outputs, e.g. the
  /// card-location model). A new list; [input] has [inputSize] values.
  Float64List predictAll(List<double> input) {
    final typed = input is Float64List ? input : Float64List.fromList(input);
    return Float64List.fromList(_forwardTyped(typed));
  }

  /// Predict directly from a pre-filled [Float64List]. The caller is
  /// responsible for sizing the buffer to [inputSize] and filling it on
  /// every call; this entry point skips both the type check and the
  /// allocation in [predict].
  double predictBuffer(Float64List input) => _forwardTyped(input)[0];

  // ── Incremental first layer ─────────────────────────────────────────────
  //
  // For inputs that differ only in a few sparse entries (e.g. scoring every
  // schupf candidate: same hand, different one-hot card slots), compute the
  // first layer's pre-activation once and add weight columns per candidate.

  /// `W0 · input + b0` (first layer, before ReLU) as a new buffer.
  Float64List firstLayerPreActivation(Float64List input) {
    final w = _weights[0];
    final b = _biases[0];
    final inLen = inputSize;
    final out = Float64List(b.length);
    for (var j = 0; j < b.length; j++) {
      var sum = b[j];
      final base = j * inLen;
      for (var i = 0; i < inLen; i++) {
        final x = input[i];
        if (x != 0) sum += w[base + i] * x;
      }
      out[j] = sum;
    }
    return out;
  }

  /// Adds `scale * W0[:, inputIndex]` to [pre].
  void addFirstLayerColumn(
    Float64List pre,
    int inputIndex, [
    double scale = 1.0,
  ]) {
    final w = _weights[0];
    final inLen = inputSize;
    for (var j = 0; j < pre.length; j++) {
      pre[j] += w[j * inLen + inputIndex] * scale;
    }
  }

  /// Output (first unit) given the first layer's pre-activation [pre].
  double predictFromFirstLayer(Float64List pre) {
    if (numLayers == 1) return pre[0];
    var inBuf = _buffers[0];
    for (var j = 0; j < pre.length; j++) {
      inBuf[j] = pre[j] < 0 ? 0.0 : pre[j];
    }
    var inLen = pre.length;
    for (var l = 1; l < numLayers; l++) {
      final w = _weights[l];
      final b = _biases[l];
      final outLen = b.length;
      final out = _buffers[l];
      final isHidden = l < numLayers - 1;
      for (var j = 0; j < outLen; j++) {
        var sum = b[j];
        final base = j * inLen;
        for (var i = 0; i < inLen; i++) {
          sum += w[base + i] * inBuf[i];
        }
        out[j] = isHidden && sum < 0 ? 0.0 : sum;
      }
      inBuf = out;
      inLen = outLen;
    }
    return _buffers.last[0];
  }

  // ── Shared-prefix scoring ───────────────────────────────────────────────

  /// Column-major copies of the weights (`[l][i * outSize + j]`), so the
  /// contribution of one input can be added with a contiguous loop.
  late final List<Float64List> _transposed = [
    for (var l = 0; l < numLayers; l++) _transpose(l),
  ];

  Float64List _transpose(int l) {
    final inLen = layerSizes[l];
    final outLen = layerSizes[l + 1];
    final w = _weights[l];
    final t = Float64List(w.length);
    for (var j = 0; j < outLen; j++) {
      for (var i = 0; i < inLen; i++) {
        t[i * outLen + j] = w[j * inLen + i];
      }
    }
    return t;
  }

  /// Fast scorer for many inputs that share their first [prefixLength]
  /// entries (state features) and differ in the rest (action features).
  MlpPrefixScorer prefixScorer(int prefixLength) {
    if (prefixLength < 0 || prefixLength > inputSize) {
      throw ArgumentError.value(prefixLength, 'prefixLength');
    }
    return MlpPrefixScorer._(this, prefixLength);
  }

  /// [prefixScorer] with 4-wide float32 SIMD. About 3x faster when compiled
  /// ahead of time (headless training runs); results differ from the
  /// float64 scorer only by float32 rounding (~1e-6 relative).
  MlpSimdPrefixScorer simdPrefixScorer(int prefixLength) {
    if (prefixLength < 0 || prefixLength > inputSize) {
      throw ArgumentError.value(prefixLength, 'prefixLength');
    }
    return MlpSimdPrefixScorer._(this, prefixLength);
  }

  /// Column-major float32 weights, every column padded with zeros to a
  /// multiple of four outputs (`[l][i * vecLen(l) + v]`).
  late final List<Float32x4List> _simdWeights = [
    for (var l = 0; l < numLayers; l++) _simdTranspose(l),
  ];

  late final List<Float32x4List> _simdBiases = [
    for (var l = 0; l < numLayers; l++) _simdBias(l),
  ];

  int _vecLen(int l) => (layerSizes[l + 1] + 3) ~/ 4;

  /// Layer [l]'s weights as float32, column-major with every input row
  /// padded to a multiple of four outputs (`[i * 4 * vec + j]`), and its
  /// padded bias: the layout of the SIMD scorers (and the web's wasm
  /// kernel, `web_kernel/mlp_kernel.c`).
  Float32List simdWeightLayout(int l) =>
      Float32List.view(_simdWeights[l].buffer);
  Float32List simdBiasLayout(int l) => Float32List.view(_simdBiases[l].buffer);

  Float32x4List _simdTranspose(int l) {
    final inLen = layerSizes[l];
    final outLen = layerSizes[l + 1];
    final vecLen = _vecLen(l);
    final w = _weights[l];
    final flat = Float32List(inLen * vecLen * 4);
    for (var j = 0; j < outLen; j++) {
      for (var i = 0; i < inLen; i++) {
        flat[i * vecLen * 4 + j] = w[j * inLen + i];
      }
    }
    return Float32x4List.view(flat.buffer);
  }

  Float32x4List _simdBias(int l) {
    final flat = Float32List(_vecLen(l) * 4);
    final b = _biases[l];
    for (var j = 0; j < b.length; j++) {
      flat[j] = b[j];
    }
    return Float32x4List.view(flat.buffer);
  }

  // ── Safetensors loading ─────────────────────────────────────────────────

  /// Load weights from a safetensors binary file.
  ///
  /// The safetensors format (https://huggingface.co/docs/safetensors):
  ///   - 8 bytes: little-endian uint64 header length N
  ///   - N bytes: UTF-8 JSON header with tensor descriptors + __metadata__
  ///   - remaining: raw tensor data
  ///
  /// Returns `(mlp, targetMean, targetStd)`.
  static (Mlp, double, double) fromSafetensorsBytes(Uint8List bytes) {
    // Read header length (LE uint64) as two uint32 halves: dart2js (the web
    // build) has no 64-bit accessors.
    final lengthBytes = ByteData.sublistView(bytes, 0, 8);
    final headerLen =
        lengthBytes.getUint32(0, Endian.little) +
        lengthBytes.getUint32(4, Endian.little) * 0x100000000;
    final headerJson = utf8.decode(bytes.sublist(8, 8 + headerLen));
    final header = jsonDecode(headerJson) as Map<String, dynamic>;
    final dataOffset = 8 + headerLen;

    // Extract metadata.
    final meta = header['__metadata__'] as Map<String, dynamic>? ?? {};
    final layerSizes = (jsonDecode(
      meta['layer_sizes'] as String? ?? '[]',
    ) as List).cast<int>();
    final targetMean =
        double.tryParse(meta['target_mean']?.toString() ?? '') ?? 0.0;
    final targetStd =
        double.tryParse(meta['target_std']?.toString() ?? '') ?? 1.0;

    if (layerSizes.length < 2) {
      throw StateError('Invalid safetensors: layer_sizes=$layerSizes');
    }

    final numLinearLayers = layerSizes.length - 1;
    final weights = <Float64List>[];
    final biases = <Float64List>[];

    for (var l = 0; l < numLinearLayers; l++) {
      // Read weight tensor: "layer.{l}.weight" — float32, shape (out, in).
      final wInfo = header['layer.$l.weight'] as Map<String, dynamic>;
      final wOffsets = (wInfo['data_offsets'] as List).cast<int>();
      final wBytes = bytes.sublist(
        dataOffset + wOffsets[0],
        dataOffset + wOffsets[1],
      );
      final wFloat32 = Float32List.sublistView(
        wBytes.buffer
            .asByteData(wBytes.offsetInBytes, wBytes.length)
            .buffer
            .asUint8List(wBytes.offsetInBytes, wBytes.length),
      );
      // Convert float32 → float64 into a contiguous Float64List.
      final w = Float64List(wFloat32.length);
      for (var i = 0; i < wFloat32.length; i++) {
        w[i] = wFloat32[i];
      }
      weights.add(w);

      // Read bias tensor: "layer.{l}.bias" — float32, shape (out,).
      final bInfo = header['layer.$l.bias'] as Map<String, dynamic>;
      final bOffsets = (bInfo['data_offsets'] as List).cast<int>();
      final bBytes = bytes.sublist(
        dataOffset + bOffsets[0],
        dataOffset + bOffsets[1],
      );
      final bFloat32 = Float32List.sublistView(
        bBytes.buffer
            .asByteData(bBytes.offsetInBytes, bBytes.length)
            .buffer
            .asUint8List(bBytes.offsetInBytes, bBytes.length),
      );
      final b = Float64List(bFloat32.length);
      for (var i = 0; i < bFloat32.length; i++) {
        b[i] = bFloat32[i];
      }
      biases.add(b);
    }

    return (
      Mlp._(weights: weights, biases: biases, layerSizes: layerSizes),
      targetMean,
      targetStd,
    );
  }
}

/// Scores the legal actions of one decision: [setPrefix] once with the
/// state features, then [score] per action.
abstract interface class PrefixScorer {
  void setPrefix(List<double> prefix);
  double score(List<double> suffix, [int offset]);
}

/// Builds a [PrefixScorer] for [net] with [prefixLength] shared inputs.
typedef PrefixScorerFactory = PrefixScorer Function(Mlp net, int prefixLength);

/// Scores inputs of an [Mlp] (first output unit) that share a prefix.
///
/// The first layer's contribution of the prefix is computed once per
/// [setPrefix]; every [score] call then only adds the suffix. All layers
/// skip zero inputs (card bitmaps and ReLU outputs are mostly zero), which
/// makes scoring the legal actions of one decision several times cheaper
/// than a dense forward pass per action. Results equal [Mlp.predictBuffer]
/// up to floating-point summation order.
class MlpPrefixScorer implements PrefixScorer {
  final Mlp _net;
  final int prefixLength;
  final Float64List _base;
  final List<Float64List> _acts;

  MlpPrefixScorer._(this._net, this.prefixLength)
    : _base = Float64List(_net.layerSizes[1]),
      _acts = [
        for (var l = 1; l < _net.layerSizes.length; l++)
          Float64List(_net.layerSizes[l]),
      ];

  int get suffixLength => _net.inputSize - prefixLength;

  /// Set the shared prefix (the first [prefixLength] inputs).
  @override
  void setPrefix(List<double> prefix) {
    final bias = _net._biases[0];
    final wt = _net._transposed[0];
    final outLen = bias.length;
    final base = _base;
    for (var j = 0; j < outLen; j++) {
      base[j] = bias[j];
    }
    for (var i = 0; i < prefixLength; i++) {
      final x = prefix[i];
      if (x == 0) continue;
      final off = i * outLen;
      for (var j = 0; j < outLen; j++) {
        base[j] += x * wt[off + j];
      }
    }
  }

  /// Network output for the current prefix followed by [suffix]
  /// (read from [offset], [suffixLength] entries).
  @override
  double score(List<double> suffix, [int offset = 0]) {
    final net = _net;
    var cur = _acts[0];
    var curLen = cur.length;
    final base = _base;
    for (var j = 0; j < curLen; j++) {
      cur[j] = base[j];
    }
    final wt0 = net._transposed[0];
    final n = suffixLength;
    for (var i = 0; i < n; i++) {
      final x = suffix[offset + i];
      if (x == 0) continue;
      final off = (prefixLength + i) * curLen;
      for (var j = 0; j < curLen; j++) {
        cur[j] += x * wt0[off + j];
      }
    }
    for (var l = 1; l < net.numLayers; l++) {
      final bias = net._biases[l];
      final wt = net._transposed[l];
      final next = _acts[l];
      final outLen = bias.length;
      for (var j = 0; j < outLen; j++) {
        next[j] = bias[j];
      }
      for (var i = 0; i < curLen; i++) {
        final x = cur[i];
        if (x <= 0) continue; // ReLU
        final off = i * outLen;
        for (var j = 0; j < outLen; j++) {
          next[j] += x * wt[off + j];
        }
      }
      cur = next;
      curLen = outLen;
    }
    return cur[0];
  }
}

/// [MlpPrefixScorer] on 4-wide float32 SIMD vectors (see
/// [Mlp.simdPrefixScorer]). Padded outputs have zero weights and biases, so
/// they stay zero and are skipped like any inactive ReLU unit.
///
/// Every layer first collects its non-zero inputs, then accumulates each
/// block of output vectors in registers over them ([_accumulate]). Each
/// output still receives `bias + w_i * x_i` in increasing input order, one
/// float32 multiply and add at a time, so the result is bit for bit that of
/// the straightforward "add one input column at a time" loop.
class MlpSimdPrefixScorer implements PrefixScorer {
  final Mlp _net;
  final int prefixLength;
  final Float32x4List _base;
  final List<Float32x4List> _acts;

  /// Scalar views of [_acts] (same memory) for the ReLU test.
  final List<Float32List> _scalar;

  /// The non-zero inputs of the layer being computed: offset of their weight
  /// row (in vectors) and their value, splatted.
  final Int32List _rows;
  final Float32x4List _xs;

  MlpSimdPrefixScorer._(this._net, this.prefixLength)
    : _base = Float32x4List(_net._vecLen(0)),
      _acts = [
        for (var l = 0; l < _net.numLayers; l++) Float32x4List(_net._vecLen(l)),
      ],
      _scalar = [],
      _rows = Int32List(_net.layerSizes.reduce(max)),
      _xs = Float32x4List(_net.layerSizes.reduce(max)) {
    for (final a in _acts) {
      _scalar.add(Float32List.view(a.buffer));
    }
  }

  int get suffixLength => _net.inputSize - prefixLength;

  @override
  void setPrefix(List<double> prefix) {
    final vecLen = _base.length;
    final rows = _rows;
    final xs = _xs;
    var n = 0;
    if (prefix is Float64List) {
      // Typed reads (no boxed doubles); the same values as below.
      for (var i = 0; i < prefixLength; i++) {
        final x = prefix[i];
        if (x == 0) continue;
        rows[n] = i * vecLen;
        xs[n] = Float32x4.splat(x);
        n++;
      }
    } else {
      for (var i = 0; i < prefixLength; i++) {
        final x = prefix[i];
        if (x == 0) continue;
        rows[n] = i * vecLen;
        xs[n] = Float32x4.splat(x);
        n++;
      }
    }
    _accumulate(_base, _net._simdBiases[0], _net._simdWeights[0], n);
  }

  @override
  double score(List<double> suffix, [int offset = 0]) {
    final net = _net;
    final rows = _rows;
    final xs = _xs;
    final vecLen = _base.length;
    final n = suffixLength;
    var k = 0;
    if (suffix is Float64List) {
      for (var i = 0; i < n; i++) {
        final x = suffix[offset + i];
        if (x == 0) continue;
        rows[k] = (prefixLength + i) * vecLen;
        xs[k] = Float32x4.splat(x);
        k++;
      }
    } else {
      for (var i = 0; i < n; i++) {
        final x = suffix[offset + i];
        if (x == 0) continue;
        rows[k] = (prefixLength + i) * vecLen;
        xs[k] = Float32x4.splat(x);
        k++;
      }
    }
    _accumulate(_acts[0], _base, net._simdWeights[0], k);
    for (var l = 1; l < net.numLayers; l++) {
      final nextLen = _acts[l].length;
      final cur = _scalar[l - 1];
      final inLen = net.layerSizes[l];
      k = 0;
      for (var i = 0; i < inLen; i++) {
        final x = cur[i];
        if (x <= 0) continue; // ReLU
        rows[k] = i * nextLen;
        xs[k] = Float32x4.splat(x);
        k++;
      }
      _accumulate(_acts[l], net._simdBiases[l], net._simdWeights[l], k);
    }
    return _scalar[net.numLayers - 1][0];
  }

  /// `out[v] = init[v] + sum_k w[rows[k] + v] * xs[k]` for every output
  /// vector v, adding the terms in order k = 0, 1, ...; blocks of output
  /// vectors stay in registers while the [n] inputs are added.
  @pragma('vm:unsafe:no-bounds-checks')
  void _accumulate(
    Float32x4List out,
    Float32x4List init,
    Float32x4List w,
    int n,
  ) {
    final rows = _rows;
    final xs = _xs;
    final len = out.length;
    // The loops below skip bounds checks; rows are increasing.
    if (init.length < len ||
        rows.length < n ||
        xs.length < n ||
        (n > 0 && rows[n - 1] + len > w.length)) {
      throw RangeError('MlpSimdPrefixScorer: buffers too small');
    }
    var v = 0;
    for (; v + 8 <= len; v += 8) {
      var a0 = init[v];
      var a1 = init[v + 1];
      var a2 = init[v + 2];
      var a3 = init[v + 3];
      var a4 = init[v + 4];
      var a5 = init[v + 5];
      var a6 = init[v + 6];
      var a7 = init[v + 7];
      for (var k = 0; k < n; k++) {
        final x = xs[k];
        final o = rows[k] + v;
        a0 += w[o] * x;
        a1 += w[o + 1] * x;
        a2 += w[o + 2] * x;
        a3 += w[o + 3] * x;
        a4 += w[o + 4] * x;
        a5 += w[o + 5] * x;
        a6 += w[o + 6] * x;
        a7 += w[o + 7] * x;
      }
      out[v] = a0;
      out[v + 1] = a1;
      out[v + 2] = a2;
      out[v + 3] = a3;
      out[v + 4] = a4;
      out[v + 5] = a5;
      out[v + 6] = a6;
      out[v + 7] = a7;
    }
    for (; v < len; v++) {
      var a = init[v];
      for (var k = 0; k < n; k++) {
        a += w[rows[k] + v] * xs[k];
      }
      out[v] = a;
    }
  }
}

double _gaussian(Random rng) {
  final u1 = rng.nextDouble();
  final u2 = rng.nextDouble();
  return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
}
