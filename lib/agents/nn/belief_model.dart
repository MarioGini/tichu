import 'dart:math';

import 'package:tichu/agents/card_knowledge.dart';
import 'package:tichu/agents/nn/feature_encoder.dart';
import 'package:tichu/agents/nn/mlp.dart';
import 'package:tichu/agents/partner_convention.dart';
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
  ///
  /// With [convention] the net reads the partner's promise from its
  /// inputs, and a promise that rules a side out is applied exactly
  /// ([applyHighCardRead]: e.g. no high card with a partner who passed an
  /// even card).
  List<List<double>> holderProbabilities(
    GameSnapshot snapshot,
    String playerId, {
    PartnerConvention convention = PartnerConvention.free,
  }) {
    final out = network.predictAll(
      encodeStateFeatures(
        snapshot: snapshot,
        playerId: playerId,
        convention: convention,
      ),
    );
    return applyHighCardRead(
      [
        for (var slot = 0; slot < CardKnowledge.slotCount; slot++)
          _softmax(out[slot * 3], out[slot * 3 + 1], out[slot * 3 + 2]),
      ],
      readPartnerPromiseAt(
        convention: convention,
        playerId: playerId,
        players: snapshot.players,
        hands: snapshot.hands,
        roundLog: snapshot.roundLog,
        selections: snapshot.schupfSelections,
        calls: snapshot.scoreState.tichuCalls,
      ),
    );
  }

  static List<double> _softmax(double a, double b, double c) {
    final m = max(a, max(b, c));
    final ea = exp(a - m);
    final eb = exp(b - m);
    final ec = exp(c - m);
    final z = ea + eb + ec;
    return [_grid(ea / z), _grid(eb / z), _grid(ec / z)];
  }

  /// Rounded to a multiple of 2^-30: `exp` differs in the last bit
  /// between the Dart VM and JavaScript, and the search deals its worlds
  /// from these values, so without rounding the web's bots drifted from
  /// the native ones (the ones the duels measure) after a few dozen moves.
  static double _grid(double p) => (p * _scale).roundToDouble() / _scale;
  static const double _scale = 1073741824;
}
