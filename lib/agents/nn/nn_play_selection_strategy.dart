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
class NnPlaySelectionStrategy
    implements PlaySelectionStrategy, FullTurnPolicy {
  final String playerId;
  final Mlp network;
  final PlaySelectionStrategy fallback;

  /// Pre-allocated typed input buffer reused across [selectPlay] calls.
  /// Avoids ~7 list allocations per decision in a typical play phase
  /// (one per legal action) — matters because [Mlp.predict] is the hot
  /// path of headless self-play.
  late final Float64List _inputBuffer = Float64List(network.inputSize);

  NnPlaySelectionStrategy({
    required this.playerId,
    required this.network,
    this.fallback = const DefaultPlaySelectionStrategy(),
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
    final stateFeatures = encoder.stateFeatures;

    // Fill the state-features prefix once; the action suffix changes per
    // legal play and is overwritten on each iteration.
    final buffer = _inputBuffer;
    final stateLen = stateFeatures.length;
    for (var i = 0; i < stateLen; i++) {
      buffer[i] = stateFeatures[i];
    }

    TichuTurn? bestPlay;
    var bestValue = double.negativeInfinity;

    for (final play in plays) {
      encoder.writeActionFeatures(play, buffer, stateLen);
      final qValue = network.predictBuffer(buffer);

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
        stateLen,
        isPass: true,
      );
      if (network.predictBuffer(buffer) > bestValue) return null;
    }

    return bestPlay ?? plays.first;
  }
}
