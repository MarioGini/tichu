import 'dart:math';

import 'package:tichu/agents/card_knowledge.dart';
import 'package:tichu/agents/nn/feature_encoder.dart';
import 'package:tichu/agents/nn/mlp.dart';
import 'package:tichu/game/game_snapshot.dart';

/// Card-location model (`rl/belief_train.py`): for every card the decider
/// cannot see, the probability that the left opponent, the partner or the
/// right opponent holds it, from the decider's state features.
class BeliefModel {
  final Mlp network;

  BeliefModel(this.network) {
    if (network.inputSize != stateFeatureCount) {
      throw ArgumentError.value(
        network.inputSize,
        'network.inputSize',
        'Belief net must take the $stateFeatureCount state features.',
      );
    }
  }

  /// `p[slot][k]` for card slot 0..55 and k = 0 left opponent, 1 partner,
  /// 2 right opponent (softmax of the net's 56 x 3 logits).
  List<List<double>> holderProbabilities(
    GameSnapshot snapshot,
    String playerId,
  ) {
    final out = network.predictAll(
      encodeStateFeatures(snapshot: snapshot, playerId: playerId),
    );
    return [
      for (var slot = 0; slot < CardKnowledge.slotCount; slot++)
        _softmax(out[slot * 3], out[slot * 3 + 1], out[slot * 3 + 2]),
    ];
  }

  static List<double> _softmax(double a, double b, double c) {
    final m = max(a, max(b, c));
    final ea = exp(a - m);
    final eb = exp(b - m);
    final ec = exp(c - m);
    final z = ea + eb + ec;
    return [ea / z, eb / z, ec / z];
  }
}
