import 'dart:math' as math;

import 'package:tichu/agents/card_knowledge.dart';
import 'package:tichu/agents/plan_play.dart';
import 'package:tichu/agents/table_relationships.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/scoring/score_data.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/card_utils.dart';

part 'turn_scorer_helpers.dart';

/// Weights of the [TurnScorer] terms. Every term was kept because removing
/// it measurably loses points (exact rollout values, see
/// `lib/agents/ai_strategy.md`).
class PolicyWeights {
  /// Leading: prefer low plays.
  final double lowLeadPreference;

  /// Penalty per Ace / Phoenix / Dragon spent on a trick we are not sure to
  /// take from an opponent.
  final double controlPreservation;

  /// Early (9+ cards): penalty per King / Ace / Phoenix / Dragon spent,
  /// scaled down on tricks with points.
  final double avoidHighBurn;

  /// Bonus per unpaired low card (<= 7) the play gets rid of.
  final double sheddingRiskyLowSingle;

  /// Bonus per card played.
  final double comboEfficiency;

  /// An opponent has 4 cards or fewer: bonus for a play nobody can beat.
  final double unbeatableLine;

  /// An opponent has 1 card: prefer multi-card plays, avoid singles.
  final double preferMultiCardWhenOpponentLow;
  final double avoidSingleWhenOpponentLow;

  /// Penalty per point (5 / 10 / K) of my own cards played into a trick I
  /// am not sure to win.
  final double pointGift;

  /// Penalty per extra play a move adds to the hand's plays-to-go-out
  /// (breaking a straight / pair / full house).
  final double planEfficiency;

  const PolicyWeights({
    this.lowLeadPreference = 2,
    this.controlPreservation = 6,
    this.avoidHighBurn = 4,
    this.sheddingRiskyLowSingle = 2,
    this.comboEfficiency = 2,
    this.unbeatableLine = 2.5,
    this.preferMultiCardWhenOpponentLow = 4,
    this.avoidSingleWhenOpponentLow = 4,
    this.pointGift = 0.15,
    this.planEfficiency = 2.5,
  });

  /// These weights with the named [overrides] applied (A/B testing; names
  /// are the field names).
  PolicyWeights withOverrides(Map<String, double> overrides) {
    if (overrides.isEmpty) return this;
    final v = <String, double>{
      'lowLeadPreference': lowLeadPreference,
      'controlPreservation': controlPreservation,
      'avoidHighBurn': avoidHighBurn,
      'sheddingRiskyLowSingle': sheddingRiskyLowSingle,
      'comboEfficiency': comboEfficiency,
      'unbeatableLine': unbeatableLine,
      'preferMultiCardWhenOpponentLow': preferMultiCardWhenOpponentLow,
      'avoidSingleWhenOpponentLow': avoidSingleWhenOpponentLow,
      'pointGift': pointGift,
      'planEfficiency': planEfficiency,
    };
    for (final e in overrides.entries) {
      if (!v.containsKey(e.key)) {
        throw ArgumentError('Unknown scorer weight: ${e.key}');
      }
      v[e.key] = e.value;
    }
    return PolicyWeights(
      lowLeadPreference: v['lowLeadPreference']!,
      controlPreservation: v['controlPreservation']!,
      avoidHighBurn: v['avoidHighBurn']!,
      sheddingRiskyLowSingle: v['sheddingRiskyLowSingle']!,
      comboEfficiency: v['comboEfficiency']!,
      unbeatableLine: v['unbeatableLine']!,
      preferMultiCardWhenOpponentLow: v['preferMultiCardWhenOpponentLow']!,
      avoidSingleWhenOpponentLow: v['avoidSingleWhenOpponentLow']!,
      pointGift: v['pointGift']!,
      planEfficiency: v['planEfficiency']!,
    );
  }
}

class TurnScorer {
  final PolicyWeights weights;

  const TurnScorer({this.weights = const PolicyWeights()});

  double scoreTurn(
    GameSnapshot snapshot,
    String playerId,
    TichuTurn play,
    DeckState deck,
    List<Card> hand,
  ) {
    if (play.cards.length == hand.length) {
      return 1000;
    }

    var score = 0.0;
    final knowledge = CardKnowledge.of(snapshot, playerId);
    // Wins the trick for sure (bombs aside): spending high cards on it is
    // not a waste, it converts them into a guaranteed trick and the lead.
    final sureWin = play.type != TurnType.bomb && knowledge.isUnbeatable(play);

    final isLeading =
        deck.turn.type == TurnType.empty ||
        deck.turn.type == TurnType.none ||
        deck.turn.type == TurnType.dog;

    final isEarly = hand.length >= 9;
    // Points of the whole trick so far (not just the top combination).
    final trickPoints = isLeading
        ? 0
        : math.max(snapshot.trickPoints, pointsForCards(deck.turn.cards));

    const maxValue = 25.0;
    final lowValueFactor = (maxValue - play.value) / maxValue;

    if (isLeading) {
      score += weights.lowLeadPreference * lowValueFactor;
    }

    score += weights.comboEfficiency * play.cards.length;

    const controlCards = <CardFace>{
      CardFace.dragon,
      CardFace.phoenix,
      CardFace.ace,
    };
    const highCards = <CardFace>{
      CardFace.dragon,
      CardFace.phoenix,
      CardFace.ace,
      CardFace.king,
    };

    final controlCount = play.cards
        .where((card) => controlCards.contains(card.face))
        .length;
    final table = TableRelationships(snapshot, playerId);
    final winnerId = deck.currentWinner.isNotEmpty
        ? deck.currentWinner
        : snapshot.lastPlayedBy;
    final opponentWinning =
        !isLeading && winnerId != null && table.isOpponent(winnerId);
    final sureCapture = sureWin && opponentWinning;

    if (controlCount > 0 && !sureCapture) {
      score -= weights.controlPreservation * controlCount;
    }

    if (isEarly && !sureCapture) {
      final pointFactor = (trickPoints / 25).clamp(0, 1).toDouble();
      final highCount = play.cards
          .where((card) => highCards.contains(card.face))
          .length;
      if (highCount > 0) {
        score -= weights.avoidHighBurn * highCount * (1 - pointFactor);
      }
    }

    // Don't feed own point cards into a trick we are not sure to win
    // (unless an opponent who called Tichu is about to go out with it).
    if (!sureWin &&
        !_opponentTichuNearFinishWinningTrick(snapshot, playerId, deck)) {
      final ownPoints = pointsForCards(play.cards);
      if (ownPoints > 0) score -= weights.pointGift * ownPoints;
    }

    if (weights.planEfficiency != 0) {
      score -= weights.planEfficiency * PlanPlay.planCost(hand, play);
    }

    final beforeSingles = _countLowSingletons(hand);
    final remaining = _removePlayedCards(hand, play.cards);
    final afterSingles = _countLowSingletons(remaining);
    final deltaSingles = beforeSingles - afterSingles;
    if (deltaSingles != 0) {
      score += weights.sheddingRiskyLowSingle * deltaSingles;
    }

    if (_opponentLow(snapshot, playerId) &&
        _isUnbeatableLine(play, knowledge)) {
      score += weights.unbeatableLine;
    }

    if (_opponentAtOne(snapshot, playerId)) {
      if (play.cards.length >= 2) {
        score += weights.preferMultiCardWhenOpponentLow;
      } else if (play.type == TurnType.single) {
        score -= weights.avoidSingleWhenOpponentLow;
      }
    }

    return score;
  }
}
