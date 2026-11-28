import 'dart:math';
import 'dart:typed_data';

import 'package:tichu/agents/card_knowledge.dart';
import 'package:tichu/agents/nn/feature_encoder.dart';
import 'package:tichu/agents/nn/mlp.dart';
import 'package:tichu/agents/table_relationships.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// Inputs of the value net: the player's state features followed by who
/// really holds every card (card slot x left opponent / partner / right
/// opponent, one-hot).
const int valueHolderFeatureCount = CardKnowledge.slotCount * 3;
const int valueFeatureCount = stateFeatureCount + valueHolderFeatureCount;

/// Outputs of the value net (`rl/value_train.py`), in this order: the round
/// points of the player's team and of the other team (in units of the
/// net's `target_std`), who goes out first (logits: self, left, partner,
/// right) and the double victory (logits: us, them, neither).
const int valueOutputCount = 2 + 4 + 3;

/// What the value net predicts for the rest of a round.
class ValueEstimate {
  /// Expected round points of the player's team and of the other team.
  final double us;
  final double them;

  /// P(first out) for self, left opponent, partner, right opponent.
  final List<double> firstOut;

  /// P(double victory) for us, them, neither.
  final List<double> doubleWin;

  const ValueEstimate(this.us, this.them, this.firstOut, this.doubleWin);

  double get diff => us - them;
}

/// Perfect-information value net: the round outcome from the full deal
/// (every hand known) as seen by the player to move.
///
/// It is the leaf evaluator of a truncated search: a playout stops after a
/// few moves and the net guesses the rest, so a search can afford many
/// more worlds and candidate moves than full rollouts allow (the
/// tichuengine.com search reports such a "value net, true state" next to
/// its tree). It sees the true hands, so it is only for states inside a
/// world (a re-deal), never for the real game.
class ValueModel {
  final Mlp network;

  /// Points per output unit (the net's `target_std`).
  final double scale;

  ValueModel(this.network, {this.scale = 100}) {
    if (network.inputSize != valueFeatureCount) {
      throw ArgumentError.value(
        network.inputSize,
        'network.inputSize',
        'Value net must take the $valueFeatureCount value features.',
      );
    }
    if (network.layerSizes.last != valueOutputCount) {
      throw ArgumentError.value(
        network.layerSizes.last,
        'network outputs',
        'Value net must have $valueOutputCount outputs.',
      );
    }
  }

  ValueEstimate estimate(GameSnapshot snapshot, String playerId) {
    final out = network.predictAll(encodeValueFeatures(snapshot, playerId));
    return ValueEstimate(
      out[0] * scale,
      out[1] * scale,
      _softmax(out, 2, 4),
      _softmax(out, 6, 3),
    );
  }

  static List<double> _softmax(Float64List x, int from, int n) {
    var m = x[from];
    for (var i = 1; i < n; i++) {
      m = max(m, x[from + i]);
    }
    final e = [for (var i = 0; i < n; i++) exp(x[from + i] - m)];
    final z = e.reduce((a, b) => a + b);
    return [for (final v in e) v / z];
  }
}

/// The value net's inputs for [playerId] in [snapshot], whose hands are
/// all known (a world of the search, or a training position).
List<double> encodeValueFeatures(GameSnapshot snapshot, String playerId) {
  final table = TableRelationships(snapshot, playerId);
  final holders = [
    table.playerBySeat(table.leftSeat()).id,
    table.partnerId!,
    table.playerBySeat(table.rightSeat()).id,
  ];
  final out = List<double>.filled(valueFeatureCount, 0);
  final state = encodeStateFeatures(snapshot: snapshot, playerId: playerId);
  out.setRange(0, stateFeatureCount, state);
  for (var k = 0; k < 3; k++) {
    for (final card in snapshot.hands[holders[k]] ?? const <Card>[]) {
      final slot = cardSlot(card);
      if (slot >= 0) out[stateFeatureCount + slot * 3 + k] = 1;
    }
  }
  return out;
}
