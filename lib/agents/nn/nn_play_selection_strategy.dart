import 'dart:typed_data';

import 'package:tichu/agents/legal_play_guard.dart';
import 'package:tichu/agents/nn/feature_encoder.dart';
import 'package:tichu/agents/nn/mlp.dart';
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
  late final PrefixScorer _scorer = simd
      ? network.simdPrefixScorer(_stateLength)
      : network.prefixScorer(_stateLength);

  /// State prefix the net was trained on: nets from before the `history`
  /// group (v3, v4) read only the first [legacyStateFeatureCount] features.
  late final int _stateLength = network.inputSize == legacyTotalFeatureCount
      ? legacyStateFeatureCount
      : stateFeatureCount;

  /// Use float32 SIMD inference (headless runs; see [Mlp.simdPrefixScorer]).
  final bool simd;
  final Float64List _actionBuffer = Float64List(actionFeatureCount);

  NnPlaySelectionStrategy({
    required this.playerId,
    required this.network,
    this.fallback = const DefaultPlaySelectionStrategy(),
    this.simd = false,
  }) {
    if (network.inputSize != totalFeatureCount &&
        network.inputSize != legacyTotalFeatureCount) {
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
    final GameSnapshot snapshot,
    final List<TichuTurn> plays,
    final DeckState deck,
    final List<Card> hand,
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
    final GameSnapshot snapshot,
    final List<TichuTurn> legalTurns,
    final DeckState deck,
    final List<Card> hand, {
    required final bool canPass,
  }) {
    if (legalTurns.isEmpty) {
      if (canPass) return null;
      throw StateError('No legal plays and pass is illegal.');
    }
    if (legalTurns.length == 1 && !canPass) return legalTurns.first;
    return _argmax(snapshot, legalTurns, canPass: canPass);
  }

  /// Highest-Q play among [plays], or `null` when [canPass] and the pass
  /// action scores strictly highest.
  TichuTurn? _argmax(
    final GameSnapshot snapshot,
    final List<TichuTurn> plays, {
    required final bool canPass,
  }) {
    final encoder = FeatureEncoder(snapshot: snapshot, playerId: playerId);
    final scorer = _scorer..setPrefix(encoder.stateFeatures);
    final buffer = _actionBuffer;

    TichuTurn? bestPlay;
    var bestValue = double.negativeInfinity;

    for (final play in plays) {
      encoder.writeActionFeatures(play, buffer, 0);
      final qValue = scorer.score(buffer);

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
      if (scorer.score(buffer) > bestValue) return null;
    }

    return bestPlay ?? plays.first;
  }
}
