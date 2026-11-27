import 'dart:typed_data';

import 'package:tichu/agents/legal_play_guard.dart';
import 'package:tichu/agents/nn/feature_encoder.dart';
import 'package:tichu/agents/nn/mlp.dart';
import 'package:tichu/agents/nn/style_bias.dart';
import 'package:tichu/agents/play_selection_strategy.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// Play selection strategy powered by a neural network Q-value estimator.
///
/// For each legal play (and pass when legal), encodes the (state, action) pair
/// into a fixed-size feature vector and runs it through the MLP to get a
/// Q-value estimate. Picks the action with the highest Q-value.
///
/// As a [FullTurnPolicy] it decides the whole turn (including passing), so
/// the action set it sees at inference matches the one the BC writer records
/// for training.
///
/// Falls back to [DefaultPlaySelectionStrategy] when the network is null.
class NnPlaySelectionStrategy implements PlaySelectionStrategy, FullTurnPolicy {
  final String playerId;
  final Mlp network;
  final PlaySelectionStrategy fallback;

  /// Scores every legal action of a decision: the state prefix goes through
  /// the first layer once, each action only adds its own features. This is
  /// the hot path of headless self-play and of the bots in the app.
  late final PrefixScorer _scorer =
      scorerFactory?.call(network, stateFeatureCount) ??
      (simd
          ? network.simdPrefixScorer(stateFeatureCount)
          : network.prefixScorer(stateFeatureCount));

  /// Builds the scorer instead of [simd] (the web: the wasm kernel).
  final PrefixScorerFactory? scorerFactory;

  /// Use float32 SIMD inference (headless runs; see [Mlp.simdPrefixScorer]).
  final bool simd;

  /// Style experiment: pass bonus / control-card penalty (see [StyleBias]).
  final StyleBias style;

  /// Points per unit of the net's output (its `target_std`).
  final double outputScale;
  final Float64List _actionBuffer = Float64List(actionFeatureCount);

  NnPlaySelectionStrategy({
    required this.playerId,
    required this.network,
    this.fallback = const DefaultPlaySelectionStrategy(),
    this.simd = false,
    this.scorerFactory,
    this.style = StyleBias.none,
    this.outputScale = 100,
  }) {
    if (network.inputSize != totalFeatureCount) {
      throw ArgumentError.value(
        network.inputSize,
        'network.inputSize',
        'Policy was trained for a different feature schema; expected '
            '$totalFeatureCount inputs (rl/schema/feature_spec.json). '
            'Retrain the policy.',
      );
    }
  }

  @override
  TichuTurn selectPlay(
    GameSnapshot snapshot,
    List<TichuTurn> plays,
    DeckState deck,
    List<Card> hand,
  ) {
    if (plays.isEmpty) {
      throw ArgumentError.value(plays, 'plays', 'Must not be empty.');
    }

    var legalPlays = LegalPlayGuard.strictLegalTurnsFromCandidates(
      deck: deck,
      hand: hand,
      candidates: plays,
    );

    if (legalPlays.isEmpty) {
      final recovered = LegalPlayGuard.firstLegalTurnBruteForce(
        deck: deck,
        hand: hand,
      );
      if (recovered != null) {
        legalPlays = [recovered];
      }
    }

    if (legalPlays.isEmpty) {
      throw StateError('No legal plays available for NN policy selection.');
    }

    if (legalPlays.length == 1) {
      return legalPlays.first;
    }

    return _argmax(snapshot, legalPlays, canPass: false)!;
  }

  @override
  TichuTurn? selectTurnOrPass(
    GameSnapshot snapshot,
    List<TichuTurn> legalTurns,
    DeckState deck,
    List<Card> hand, {
    required bool canPass,
  }) {
    if (legalTurns.isEmpty) {
      if (canPass) return null;
      throw StateError('No legal plays and pass is illegal.');
    }
    if (legalTurns.length == 1 && !canPass) return legalTurns.first;
    return _argmax(snapshot, legalTurns, canPass: canPass);
  }

  /// Q(s, a) of each of [plays] (same order), for ranking candidates.
  List<double> qValues(GameSnapshot snapshot, List<TichuTurn> plays) {
    final encoder = FeatureEncoder(snapshot: snapshot, playerId: playerId);
    final scorer = _scorer..setPrefix(encoder.stateFeatures);
    final values = <double>[];
    for (final play in plays) {
      encoder.writeActionFeatures(play, _actionBuffer, 0);
      values.add(scorer.score(_actionBuffer));
    }
    return values;
  }

  /// Highest-Q play among [plays], or `null` when [canPass] and the pass
  /// action scores strictly highest.
  TichuTurn? _argmax(
    GameSnapshot snapshot,
    List<TichuTurn> plays, {
    required bool canPass,
  }) {
    final encoder = FeatureEncoder(snapshot: snapshot, playerId: playerId);
    final scorer = _scorer..setPrefix(encoder.stateFeatures);
    final buffer = _actionBuffer;

    TichuTurn? bestPlay;
    var bestValue = double.negativeInfinity;
    final spendPenalty =
        style.spendPenalty != 0 &&
            (snapshot.hands[playerId]?.length ?? 0) >= style.spendMinHand
        ? style.spendPenalty / outputScale
        : 0.0;

    for (final play in plays) {
      encoder.writeActionFeatures(play, buffer, 0);
      var qValue = scorer.score(buffer);
      if (spendPenalty != 0) {
        qValue -= spendPenalty * StyleBias.controls(play);
      }

      if (qValue > bestValue) {
        bestValue = qValue;
        bestPlay = play;
      } else if (qValue == bestValue && bestPlay != null) {
        // Tie-break by lower value (prefer cheaper plays).
        if (play.value < bestPlay.value) {
          bestPlay = play;
        }
      }
    }

    if (canPass) {
      encoder.writeActionFeatures(
        TichuTurn(TurnType.none, const <Card>[]),
        buffer,
        0,
        isPass: true,
      );
      if (scorer.score(buffer) + style.passBonus / outputScale > bestValue) {
        return null;
      }
    }

    return bestPlay ?? plays.first;
  }
}
