import 'package:tichu/agents/nn/feature_encoder.dart';
import 'package:tichu/agents/nn/mlp.dart';
import 'package:tichu/agents/table_relationships.dart';
import 'package:tichu/agents/tichu_call_strategy.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// One-hot card slots received in this round's schupf from the left
/// opponent, the partner and the right opponent (3 × 56); all zeros before
/// the exchange. Lets a Tichu decision react to the partner's pass (a strong
/// card usually means "you go").
const int receivedFeatureCount = 3 * 56;

/// Per-decision call features: state features + received cards.
const int callFeatureCount = stateFeatureCount + receivedFeatureCount;

/// Input width of a call-value network: `[x, flag, flag * x]` with
/// x = call features and flag 1 = call, 0 = no call. The `flag * x` block
/// lets the effect of calling depend on the hand directly (a single flag
/// input was learned as a near-constant offset).
const int callNetInputSize = 2 * callFeatureCount + 1;

/// Received schupf cards of [playerId] as [receivedFeatureCount] values.
List<double> receivedSchupfFeatures(
  final GameSnapshot snapshot,
  final String playerId,
) {
  final out = List<double>.filled(receivedFeatureCount, 0);
  for (final (block, card) in receivedSchupfCards(snapshot, playerId)) {
    if (card != null) out[block * 56 + cardSlot(card)] = 1;
  }
  return out;
}

/// `(block, card)` for left opponent (0), partner (1), right opponent (2).
List<(int, Card?)> receivedSchupfCards(
  final GameSnapshot snapshot,
  final String playerId,
) {
  final table = TableRelationships(snapshot, playerId);
  final left = table.playerBySeat(table.leftSeat()).id;
  final right = table.playerBySeat(table.rightSeat()).id;
  final partner = table.partnerId;
  final sel = snapshot.schupfSelections;
  return [
    // My left neighbour passes to me as their right.
    (0, sel[left]?.toRight),
    (1, partner == null ? null : sel[partner]?.toPartner),
    // My right neighbour passes to me as their left.
    (2, sel[right]?.toLeft),
  ];
}

/// Builds the call-network input for call features [x] and [call].
List<double> callNetInput(final List<double> x, {required final bool call}) {
  final f = call ? 1.0 : 0.0;
  return [...x, f, for (final v in x) v * f];
}

/// Call features (state + received cards) of [playerId].
List<double> callFeatures(final GameSnapshot snapshot, final String playerId) =>
    [
      ...encodeStateFeatures(snapshot: snapshot, playerId: playerId),
      ...receivedSchupfFeatures(snapshot, playerId),
    ];

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

  /// Call-value net for a Tichu call before the schupf.
  final Mlp? preSchupfTichuNetwork;
  final double preSchupfTichuScale;
  final double tichuScale;
  final double grandTichuScale;

  /// Required advantage (in round points) before calling.
  final double margin;
  final TichuCallStrategy fallback;

  NnTichuCallStrategy({
    this.tichuNetwork,
    this.grandTichuNetwork,
    this.preSchupfTichuNetwork,
    this.preSchupfTichuScale = 100,
    this.tichuScale = 100,
    this.grandTichuScale = 100,
    this.margin = 0,
    this.fallback = const DefaultTichuCallStrategy(),
  }) {
    for (final net in [
      tichuNetwork,
      grandTichuNetwork,
      preSchupfTichuNetwork,
    ]) {
      if (net != null && net.inputSize != callNetInputSize) {
        throw ArgumentError.value(
          net.inputSize,
          'network.inputSize',
          'Call network must take $callNetInputSize inputs '
              '([x, flag, flag * x], x = state + received schupf cards). '
              'Retrain with rl/call_train.py.',
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
    final x = callFeatures(snapshot, playerId);
    final qCall = network.predict(callNetInput(x, call: true));
    final qNoCall = network.predict(callNetInput(x, call: false));
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
  Future<bool> shouldCallTichuBeforeSchupf(
    final GameSnapshot snapshot,
    final String playerId,
  ) async {
    final net = preSchupfTichuNetwork;
    if (net == null) {
      return fallback.shouldCallTichuBeforeSchupf(snapshot, playerId);
    }
    return callAdvantage(net, preSchupfTichuScale, snapshot, playerId) > margin;
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
