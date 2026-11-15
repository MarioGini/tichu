import 'dart:typed_data';

import 'package:tichu/agents/card_knowledge.dart';
import 'package:tichu/agents/nn/mlp.dart';
import 'package:tichu/agents/schupf_strategy.dart';
import 'package:tichu/agents/table_relationships.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// Schupf (card passing) feature layout, mirrored by `rl/schupf_train.py`:
///
/// | block   | size | content                                             |
/// |---------|------|-----------------------------------------------------|
/// | hand    | 56   | my 14 cards before passing (card-slot bitmap)       |
/// | left    | 56   | one-hot card passed to the left opponent            |
/// | partner | 56   | one-hot card passed to the partner                  |
/// | right   | 56   | one-hot card passed to the right opponent           |
/// | context | 4    | Grand Tichu called by me, partner, left, right      |
abstract final class SchupfFeatures {
  static const int handOffset = 0;
  static const int leftOffset = 56;
  static const int partnerOffset = 112;
  static const int rightOffset = 168;
  static const int contextOffset = 224;
  static const int size = 228;

  /// Grand Tichu flags (me, partner, left, right) for [playerId].
  static List<double> context(
    final GameSnapshot snapshot,
    final String playerId,
  ) {
    final table = TableRelationships(snapshot, playerId);
    double gt(final String? id) =>
        id != null && snapshot.scoreState.tichuCalls[id] == TichuCall.grandTichu
        ? 1.0
        : 0.0;
    return [
      gt(playerId),
      gt(table.partnerId),
      gt(table.playerBySeat(table.leftSeat()).id),
      gt(table.playerBySeat(table.rightSeat()).id),
    ];
  }

  /// Full feature vector (used for logging and tests; inference uses the
  /// incremental path in [NnSchupfStrategy]).
  static Float64List encode({
    required final List<Card> hand,
    required final Card toLeft,
    required final Card toPartner,
    required final Card toRight,
    required final List<double> context,
  }) {
    final f = Float64List(size);
    for (final c in hand) {
      f[handOffset + cardSlot(c)] = 1;
    }
    f[leftOffset + cardSlot(toLeft)] = 1;
    f[partnerOffset + cardSlot(toPartner)] = 1;
    f[rightOffset + cardSlot(toRight)] = 1;
    for (var i = 0; i < 4; i++) {
      f[contextOffset + i] = context[i];
    }
    return f;
  }
}

/// Schupf decisions from a learned value network Q(hand, pass).
///
/// Scores every assignment of three distinct hand cards to (left, partner,
/// right) — 14·13·12 = 2184 candidates — and picks the one with the highest
/// predicted round point difference. The hand/context part of the first
/// layer is computed once; each candidate only adds three weight columns.
class NnSchupfStrategy implements SchupfStrategy {
  final Mlp network;

  NnSchupfStrategy({required this.network}) {
    if (network.inputSize != SchupfFeatures.size) {
      throw ArgumentError.value(
        network.inputSize,
        'network.inputSize',
        'Schupf network must take ${SchupfFeatures.size} inputs. '
            'Retrain with rl/schupf_train.py.',
      );
    }
  }

  @override
  Future<SchupfAction> selectSchupfCards(
    final GameSnapshot snapshot,
    final String playerId,
  ) async {
    final hand = List<Card>.from(snapshot.hands[playerId] ?? const <Card>[]);
    if (hand.length < 3) {
      throw StateError('Not enough cards to schupf.');
    }

    final base = Float64List(SchupfFeatures.size);
    for (final c in hand) {
      base[SchupfFeatures.handOffset + cardSlot(c)] = 1;
    }
    final ctx = SchupfFeatures.context(snapshot, playerId);
    for (var i = 0; i < 4; i++) {
      base[SchupfFeatures.contextOffset + i] = ctx[i];
    }
    final pre = network.firstLayerPreActivation(base);
    final slots = [for (final c in hand) cardSlot(c)];
    final work = Float64List(pre.length);

    var best = double.negativeInfinity;
    var bestL = 0;
    var bestP = 1;
    var bestR = 2;
    for (var l = 0; l < hand.length; l++) {
      for (var p = 0; p < hand.length; p++) {
        if (p == l) continue;
        for (var r = 0; r < hand.length; r++) {
          if (r == l || r == p) continue;
          work.setAll(0, pre);
          network
            ..addFirstLayerColumn(work, SchupfFeatures.leftOffset + slots[l])
            ..addFirstLayerColumn(work, SchupfFeatures.partnerOffset + slots[p])
            ..addFirstLayerColumn(work, SchupfFeatures.rightOffset + slots[r]);
          final q = network.predictFromFirstLayer(work);
          if (q > best) {
            best = q;
            bestL = l;
            bestP = p;
            bestR = r;
          }
        }
      }
    }

    return SchupfAction(
      playerId: playerId,
      toLeft: hand[bestL],
      toPartner: hand[bestP],
      toRight: hand[bestR],
    );
  }
}
