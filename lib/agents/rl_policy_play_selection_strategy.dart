import 'package:tichu/agents/legal_play_guard.dart';
import 'package:tichu/agents/play_selection_strategy.dart';
import 'package:tichu/agents/rl_codec.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/turn/tichu_data.dart';

class RlPolicySelectionStats {
  int invocations = 0;
  int exactStateHits = 0;
  int coarseStateHits = 0;
  int exactSelections = 0;
  int coarseSelections = 0;
  int fallbacks = 0;

  Map<String, int> toJson() => {
    'invocations': invocations,
    'exact_state_hits': exactStateHits,
    'coarse_state_hits': coarseStateHits,
    'exact_selections': exactSelections,
    'coarse_selections': coarseSelections,
    'fallbacks': fallbacks,
  };
}

class RlPolicyTable {
  final Map<String, Map<String, double>> _stateActionValues;
  final Map<String, Map<String, double>> _coarseStateActionValues;

  const RlPolicyTable(
    this._stateActionValues, {
    final Map<String, Map<String, double>> coarseStateActionValues = const {},
  }) : _coarseStateActionValues = coarseStateActionValues;

  const RlPolicyTable.empty()
    : _stateActionValues = const {},
      _coarseStateActionValues = const {};

  bool get isEmpty =>
      _stateActionValues.isEmpty && _coarseStateActionValues.isEmpty;

  Map<String, double>? valuesForState(final String stateKey) =>
      _stateActionValues[stateKey];

  Map<String, double>? valuesForCoarseState(final String coarseStateKey) =>
      _coarseStateActionValues[coarseStateKey];

  factory RlPolicyTable.fromJsonObject(final Object? jsonObject) {
    if (jsonObject is! Map<String, dynamic>) {
      return const RlPolicyTable.empty();
    }

    final values = <String, Map<String, double>>{};
    final coarseValues = <String, Map<String, double>>{};

    final nested = jsonObject['state_action_values'];
    if (nested is Map) {
      for (final entry in nested.entries) {
        final stateKey = entry.key.toString();
        final stateValues = _parseStateActionValues(entry.value);
        if (stateValues.isNotEmpty) {
          values[stateKey] = stateValues;
        }
      }
    }

    final coarseNested = jsonObject['coarse_state_action_values'];
    if (coarseNested is Map) {
      for (final entry in coarseNested.entries) {
        final coarseStateKey = entry.key.toString();
        final stateValues = _parseStateActionValues(entry.value);
        if (stateValues.isNotEmpty) {
          coarseValues[coarseStateKey] = stateValues;
        }
      }
    }

    if (values.isEmpty && coarseValues.isEmpty) {
      return const RlPolicyTable.empty();
    }

    return RlPolicyTable(values, coarseStateActionValues: coarseValues);
  }

  static Map<String, double> _parseStateActionValues(final Object? raw) {
    if (raw is! Map) {
      return const <String, double>{};
    }

    final parsed = <String, double>{};
    for (final entry in raw.entries) {
      if (entry.value is! num) {
        continue;
      }
      parsed[entry.key.toString()] = (entry.value as num).toDouble();
    }
    return parsed;
  }
}

class RlPolicyPlaySelectionStrategy implements PlaySelectionStrategy {
  final String playerId;
  final RlPolicyTable policy;
  final PlaySelectionStrategy fallback;
  final RlPolicySelectionStats? stats;

  const RlPolicyPlaySelectionStrategy({
    required this.playerId,
    required this.policy,
    this.fallback = const DefaultPlaySelectionStrategy(),
    this.stats,
  });

  @override
  TichuTurn selectPlay(
    final GameSnapshot snapshot,
    final List<TichuTurn> plays,
    final DeckState deck,
    final List<Card> hand,
  ) {
    stats?.invocations++;
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
      throw StateError('No legal plays available for RL policy selection.');
    }

    if (policy.isEmpty) {
      stats?.fallbacks++;
      return fallback.selectPlay(snapshot, legalPlays, deck, hand);
    }

    final exactStateKey = buildRlStateKey(
      snapshot: snapshot,
      playerId: playerId,
    );
    final coarseStateKey = buildRlCoarseStateKey(
      snapshot: snapshot,
      playerId: playerId,
    );

    final exactValues = policy.valuesForState(exactStateKey);
    if (exactValues != null && exactValues.isNotEmpty) {
      stats?.exactStateHits++;
    }
    final bestExact = _selectBestPlayFromValues(
      snapshot,
      hand,
      legalPlays,
      exactValues,
    );
    if (bestExact != null) {
      stats?.exactSelections++;
      return bestExact;
    }

    final coarseValues = policy.valuesForCoarseState(coarseStateKey);
    if (coarseValues != null && coarseValues.isNotEmpty) {
      stats?.coarseStateHits++;
    }
    final bestCoarse = _selectBestPlayFromValues(
      snapshot,
      hand,
      legalPlays,
      coarseValues,
    );
    if (bestCoarse != null) {
      stats?.coarseSelections++;
      return bestCoarse;
    }

    stats?.fallbacks++;
    return fallback.selectPlay(snapshot, legalPlays, deck, hand);
  }

  TichuTurn? _selectBestPlayFromValues(
    final GameSnapshot snapshot,
    final List<Card> hand,
    final List<TichuTurn> legalPlays,
    final Map<String, double>? stateValues,
  ) {
    if (stateValues == null || stateValues.isEmpty) {
      return null;
    }

    TichuTurn? bestPlay;
    var bestValue = double.negativeInfinity;

    for (final play in legalPlays) {
      final policyKey = encodeRlPolicyPlayActionKey(
        turn: play,
        deck: snapshot.deck,
        handSize: hand.length,
      );
      final exactKey = encodeRlPlayActionKeyFromTurn(play);
      final shapeKey = encodeRlPlayShapeKeyFromTurn(play);
      final policyValue =
          stateValues[policyKey] ??
          stateValues[exactKey] ??
          stateValues[shapeKey];
      if (policyValue == null) {
        continue;
      }

      if (policyValue > bestValue) {
        bestValue = policyValue;
        bestPlay = play;
      } else if (policyValue == bestValue && bestPlay != null) {
        if (play.value < bestPlay.value) {
          bestPlay = play;
        }
      }
    }

    return bestPlay;
  }
}
