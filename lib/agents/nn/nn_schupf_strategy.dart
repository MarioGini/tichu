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
/// | context | 8    | per seat (me, partner, left, right): Grand Tichu    |
/// |         |      | called, Tichu called (e.g. announced pre-schupf)    |
abstract final class SchupfFeatures {
  static const int handOffset = 0;
  static const int leftOffset = 56;
  static const int partnerOffset = 112;
  static const int rightOffset = 168;
  static const int contextOffset = 224;
  static const int contextSize = 8;
  static const int size = 232;

  /// Call flags `[grand, tichu]` for me, partner, left, right.
  static List<double> context(
    final GameSnapshot snapshot,
    final String playerId,
  ) {
    final table = TableRelationships(snapshot, playerId);
    final out = <double>[];
    for (final id in [
      playerId,
      table.partnerId,
      table.playerBySeat(table.leftSeat()).id,
      table.playerBySeat(table.rightSeat()).id,
    ]) {
      final call = id == null ? null : snapshot.scoreState.tichuCalls[id];
      out
        ..add(call == TichuCall.grandTichu ? 1.0 : 0.0)
        ..add(call == TichuCall.tichu ? 1.0 : 0.0);
    }
    return out;
  }

  /// Bomb-safety convention shared with the heuristic: normal cards with an
  /// odd rank go to the left opponent, even ranks to the right (specials go
  /// anywhere). Partners both follow it, so an opponent never receives two
  /// cards of the same rank from us.
  static bool allowedLeft(final Card c) =>
      !_isNormal(c) || c.value.toInt().isOdd;
  static bool allowedRight(final Card c) =>
      !_isNormal(c) || c.value.toInt().isEven;

  static bool _isNormal(final Card c) =>
      c.face != CardFace.dragon &&
      c.face != CardFace.phoenix &&
      c.face != CardFace.dog &&
      c.face != CardFace.mahJong;

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
    for (var i = 0; i < SchupfFeatures.contextSize; i++) {
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
    for (var i = 0; i < SchupfFeatures.contextSize; i++) {
      base[SchupfFeatures.contextOffset + i] = ctx[i];
    }
    final pre = network.firstLayerPreActivation(base);
    final slots = [for (final c in hand) cardSlot(c)];
    final work = Float64List(pre.length);

    var best = double.negativeInfinity;
    var bestL = 0;
    var bestP = 1;
    var bestR = 2;
    // First pass respects the bomb-safety convention; only if no candidate
    // satisfies it (rare) is every assignment considered.
    for (final strict in [true, false]) {
      for (var l = 0; l < hand.length; l++) {
        if (strict && !SchupfFeatures.allowedLeft(hand[l])) continue;
        for (var p = 0; p < hand.length; p++) {
          if (p == l) continue;
          for (var r = 0; r < hand.length; r++) {
            if (r == l || r == p) continue;
            if (strict && !SchupfFeatures.allowedRight(hand[r])) continue;
            work.setAll(0, pre);
            network
              ..addFirstLayerColumn(work, SchupfFeatures.leftOffset + slots[l])
              ..addFirstLayerColumn(
                work,
                SchupfFeatures.partnerOffset + slots[p],
              )
              ..addFirstLayerColumn(
                work,
                SchupfFeatures.rightOffset + slots[r],
              );
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
      if (best > double.negativeInfinity) break;
    }

    return SchupfAction(
      playerId: playerId,
      toLeft: hand[bestL],
      toPartner: hand[bestP],
      toRight: hand[bestR],
    );
  }
}
