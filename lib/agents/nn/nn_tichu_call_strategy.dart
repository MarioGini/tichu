import 'package:tichu/agents/nn/feature_encoder.dart';
import 'package:tichu/agents/nn/mlp.dart';
import 'package:tichu/agents/tichu_call_strategy.dart';
import 'package:tichu/game/game_snapshot.dart';

/// Input width of a call-value network: the state features plus one flag
/// (1 = call, 0 = no call).
const int callNetInputSize = stateFeatureCount + 1;

/// Tichu / Grand Tichu decisions from learned call-value networks.
///
/// Each network estimates Q(s, call) — the expected round point difference
/// (own team minus opponents) when calling (`flag = 1`) or not (`flag = 0`)
/// in state `s` — as trained by `rl/call_train.py`. The agent calls when
/// `Q(s, 1) - Q(s, 0) > margin`.
///
/// A missing network falls back to [fallback] for that decision.
class NnTichuCallStrategy implements TichuCallStrategy {
  final Mlp? tichuNetwork;
  final Mlp? grandTichuNetwork;
  final double tichuScale;
  final double grandTichuScale;

  /// Required advantage (in round points) before calling.
  final double margin;
  final TichuCallStrategy fallback;

  NnTichuCallStrategy({
    this.tichuNetwork,
    this.grandTichuNetwork,
    this.tichuScale = 100,
    this.grandTichuScale = 100,
    this.margin = 0,
    this.fallback = const DefaultTichuCallStrategy(),
  }) {
    for (final net in [tichuNetwork, grandTichuNetwork]) {
      if (net != null && net.inputSize != callNetInputSize) {
        throw ArgumentError.value(
          net.inputSize,
          'network.inputSize',
          'Call network must take $callNetInputSize inputs '
              '(state features + call flag). Retrain with rl/call_train.py.',
        );
      }
    }
  }

  /// Q(s, call) - Q(s, no call) in round points.
  static double callAdvantage(
    final Mlp network,
    final double scale,
    final GameSnapshot snapshot,
    final String playerId,
  ) {
    final state = encodeStateFeatures(snapshot: snapshot, playerId: playerId);
    final input = [...state, 1.0];
    final qCall = network.predict(input);
    input[input.length - 1] = 0.0;
    final qNoCall = network.predict(input);
    return (qCall - qNoCall) * scale;
  }

  @override
  Future<bool> shouldCallGrandTichu(
    final GameSnapshot snapshot,
    final String playerId,
  ) async {
    final net = grandTichuNetwork;
    if (net == null) return fallback.shouldCallGrandTichu(snapshot, playerId);
    return callAdvantage(net, grandTichuScale, snapshot, playerId) > margin;
  }

  @override
  Future<bool> shouldCallTichu(
    final GameSnapshot snapshot,
    final String playerId,
  ) async {
    final net = tichuNetwork;
    if (net == null) return fallback.shouldCallTichu(snapshot, playerId);
    return callAdvantage(net, tichuScale, snapshot, playerId) > margin;
  }
}
