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

  Mlp._({
    required final List<Float64List> weights,
    required final List<Float64List> biases,
    required this.layerSizes,
  }) : _weights = weights,
       _biases = biases,
       _buffers = [
         for (var l = 1; l < layerSizes.length; l++) Float64List(layerSizes[l]),
       ];

  int get inputSize => layerSizes.first;
  int get outputSize => layerSizes.last;
  int get numLayers => _weights.length;

  // ── Inference ───────────────────────────────────────────────────────────

  /// Forward pass into pre-allocated [_buffers].  Returns the output buffer.
  Float64List _forward(final List<double> input) {
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
        // ReLU for hidden layers, linear for output.
        out[j] = isHidden && sum < 0 ? 0.0 : sum;
      }

      inBuf = out;
      inLen = outLen;
    }

    return _buffers.last;
  }

  /// Compute output from input features.
  List<double> forward(final List<double> input) {
    if (input.length != inputSize) {
      throw ArgumentError(
        'Expected input of size $inputSize, got ${input.length}.',
      );
    }
    return List<double>.from(_forward(input));
  }

  /// Compute Q-value for a single state-action pair (output size == 1).
  double predict(final List<double> input) => _forward(input)[0];

  // ── Safetensors loading ─────────────────────────────────────────────────

  /// Load weights from a safetensors binary file.
  ///
  /// The safetensors format (https://huggingface.co/docs/safetensors):
  ///   - 8 bytes: little-endian uint64 header length N
  ///   - N bytes: UTF-8 JSON header with tensor descriptors + __metadata__
  ///   - remaining: raw tensor data
  ///
  /// Returns `(mlp, targetMean, targetStd)`.
  static (Mlp, double, double) fromSafetensorsBytes(final Uint8List bytes) {
    // Read header length (LE uint64).
    final headerLen = ByteData.sublistView(
      bytes,
      0,
      8,
    ).getUint64(0, Endian.little);
    final headerJson = utf8.decode(bytes.sublist(8, 8 + headerLen));
    final header = jsonDecode(headerJson) as Map<String, dynamic>;
    final dataOffset = 8 + headerLen;

    // Extract metadata.
    final meta = header['__metadata__'] as Map<String, dynamic>? ?? {};
    final layerSizes =
        (jsonDecode(meta['layer_sizes'] as String? ?? '[]') as List)
            .cast<int>();
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

  // ── Random init (for tests / MCTS value baseline) ──────────────────────

  factory Mlp({required final List<int> layerSizes, final int? seed}) {
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
}

double _gaussian(final Random rng) {
  final u1 = rng.nextDouble();
  final u2 = rng.nextDouble();
  return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
}
