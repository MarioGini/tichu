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

class PolicyWeights {
  final double lowLeadPreference;
  final double controlPreservation;
  final double avoidHighBurn;
  final double sheddingRiskyLowSingle;
  final double comboEfficiency;
  final double bombUsageEarly;
  final double bombUsageLate;
  final double unbeatableLine;
  final double givePartnerLead;
  final double preferMultiCardWhenOpponentLow;
  final double avoidSingleWhenOpponentLow;
  final double supportPartnerTichu;
  final double disruptOpponentTichuNearFinish;
  final double avoidSoftLeadAgainstOpponentTichu;
  final double trickPointCapture;
  final double phoenixTrumpLeadCapture;
  final double phoenixTrumpOnAceBonus;
  final double phoenixTrumpAgainstNearFinishBonus;
  final double preserveFlexibleTrump;
  final double preferNaturalTrumpResponse;
  final double sureTrickCapture;

  /// Penalty per point (5 / 10 / K) of my own cards played into a trick I
  /// am not sure to win.
  final double pointGift;

  /// Penalty per extra play a move adds to the hand's plays-to-go-out
  /// (breaking a straight / pair / full house). 0 = off (legacy).
  final double planEfficiency;

  const PolicyWeights({
    this.lowLeadPreference = 2,
    this.controlPreservation = 3,
    this.avoidHighBurn = 4,
    this.sheddingRiskyLowSingle = 2,
    this.comboEfficiency = 2,
    this.bombUsageEarly = -6,
    this.bombUsageLate = 6,
    this.unbeatableLine = 5,
    this.givePartnerLead = 3,
    this.preferMultiCardWhenOpponentLow = 4,
    this.avoidSingleWhenOpponentLow = 4,
    this.supportPartnerTichu = 4,
    this.disruptOpponentTichuNearFinish = 8,
    this.avoidSoftLeadAgainstOpponentTichu = 4,
    this.trickPointCapture = 1,
    this.phoenixTrumpLeadCapture = 8,
    this.phoenixTrumpOnAceBonus = 6,
    this.phoenixTrumpAgainstNearFinishBonus = 5,
    this.preserveFlexibleTrump = 8,
    this.preferNaturalTrumpResponse = 6,
    this.sureTrickCapture = 4,
    this.pointGift = 0.15,
    this.planEfficiency = 0,
  });

  /// These weights with the named [overrides] applied (A/B testing; names
  /// are the field names).
  PolicyWeights withOverrides(final Map<String, double> overrides) {
    if (overrides.isEmpty) return this;
    final v = <String, double>{
      'lowLeadPreference': lowLeadPreference,
      'controlPreservation': controlPreservation,
      'avoidHighBurn': avoidHighBurn,
      'sheddingRiskyLowSingle': sheddingRiskyLowSingle,
      'comboEfficiency': comboEfficiency,
      'bombUsageEarly': bombUsageEarly,
      'bombUsageLate': bombUsageLate,
      'unbeatableLine': unbeatableLine,
      'givePartnerLead': givePartnerLead,
      'preferMultiCardWhenOpponentLow': preferMultiCardWhenOpponentLow,
      'avoidSingleWhenOpponentLow': avoidSingleWhenOpponentLow,
      'supportPartnerTichu': supportPartnerTichu,
      'disruptOpponentTichuNearFinish': disruptOpponentTichuNearFinish,
      'avoidSoftLeadAgainstOpponentTichu': avoidSoftLeadAgainstOpponentTichu,
      'trickPointCapture': trickPointCapture,
      'phoenixTrumpLeadCapture': phoenixTrumpLeadCapture,
      'phoenixTrumpOnAceBonus': phoenixTrumpOnAceBonus,
      'phoenixTrumpAgainstNearFinishBonus': phoenixTrumpAgainstNearFinishBonus,
      'preserveFlexibleTrump': preserveFlexibleTrump,
      'preferNaturalTrumpResponse': preferNaturalTrumpResponse,
      'sureTrickCapture': sureTrickCapture,
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
      bombUsageEarly: v['bombUsageEarly']!,
      bombUsageLate: v['bombUsageLate']!,
      unbeatableLine: v['unbeatableLine']!,
      givePartnerLead: v['givePartnerLead']!,
      preferMultiCardWhenOpponentLow: v['preferMultiCardWhenOpponentLow']!,
      avoidSingleWhenOpponentLow: v['avoidSingleWhenOpponentLow']!,
      supportPartnerTichu: v['supportPartnerTichu']!,
      disruptOpponentTichuNearFinish: v['disruptOpponentTichuNearFinish']!,
      avoidSoftLeadAgainstOpponentTichu:
          v['avoidSoftLeadAgainstOpponentTichu']!,
      trickPointCapture: v['trickPointCapture']!,
      phoenixTrumpLeadCapture: v['phoenixTrumpLeadCapture']!,
      phoenixTrumpOnAceBonus: v['phoenixTrumpOnAceBonus']!,
      phoenixTrumpAgainstNearFinishBonus:
          v['phoenixTrumpAgainstNearFinishBonus']!,
      preserveFlexibleTrump: v['preserveFlexibleTrump']!,
      preferNaturalTrumpResponse: v['preferNaturalTrumpResponse']!,
      sureTrickCapture: v['sureTrickCapture']!,
      pointGift: v['pointGift']!,
      planEfficiency: v['planEfficiency']!,
    );
  }
}

class TurnScorer {
  final PolicyWeights weights;

  const TurnScorer({this.weights = const PolicyWeights()});

  double scoreTurn(
    final GameSnapshot snapshot,
    final String playerId,
    final TichuTurn play,
    final DeckState deck,
    final List<Card> hand,
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
    final opponentTichuNearFinish = _opponentTichuNearFinish(
      snapshot,
      playerId,
    );
    final opponentTichuNearFinishWinning = _opponentTichuNearFinishWinningTrick(
      snapshot,
      playerId,
      deck,
    );

    const maxValue = 25.0;
    final lowValueFactor = (maxValue - play.value) / maxValue;

    if (isLeading) {
      score += weights.lowLeadPreference * lowValueFactor;
    }

    score += weights.comboEfficiency * play.cards.length;

    final controlCards = <CardFace>{
      CardFace.dragon,
      CardFace.phoenix,
      CardFace.ace,
    };
    final highCards = <CardFace>{
      CardFace.dragon,
      CardFace.phoenix,
      CardFace.ace,
      CardFace.king,
    };

    final controlCount = play.cards
        .where((final card) => controlCards.contains(card.face))
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

    if (sureCapture) {
      score += weights.sureTrickCapture;
    }

    if (isEarly && !sureCapture) {
      final pointFactor = (trickPoints / 25).clamp(0, 1).toDouble();
      final highCount = play.cards
          .where((final card) => highCards.contains(card.face))
          .length;
      if (highCount > 0) {
        score -= weights.avoidHighBurn * highCount * (1 - pointFactor);
      }
    }

    if (!isLeading && trickPoints != 0) {
      score += weights.trickPointCapture * trickPoints;
    }

    // Don't feed own point cards into a trick we are not sure to win.
    if (!sureWin && !opponentTichuNearFinishWinning) {
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

    if (play.type == TurnType.bomb) {
      if (_opponentLow(snapshot, playerId) ||
          _opponentCalledTichu(snapshot, playerId)) {
        score += weights.bombUsageLate;
      } else {
        score += weights.bombUsageEarly;
      }
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

    if (opponentTichuNearFinish) {
      if (isLeading) {
        if (play.cards.length >= 2 || _isUnbeatableLine(play, knowledge)) {
          score += weights.disruptOpponentTichuNearFinish;
        } else if (play.type == TurnType.single) {
          score -= weights.avoidSoftLeadAgainstOpponentTichu;
        }
      }
      if (!isLeading && opponentTichuNearFinishWinning) {
        final disruptionFactor = (play.value / 25).clamp(0, 1).toDouble();
        score += weights.disruptOpponentTichuNearFinish * disruptionFactor;
      }
    }

    if (play.type == TurnType.dog) {
      score += weights.givePartnerLead;
    }

    final partnerId = table.partnerId;
    if (_partnerCalledTichu(snapshot, playerId) &&
        snapshot.lastPlayedBy == partnerId &&
        deck.turn.type != TurnType.empty &&
        deck.turn.type != TurnType.none) {
      score -= weights.supportPartnerTichu;
    }

    score += _phoenixTrumpLeadScore(
      snapshot: snapshot,
      playerId: playerId,
      play: play,
      deck: deck,
      hand: hand,
      opponentTichuNearFinishWinning: opponentTichuNearFinishWinning,
    );

    score += _naturalTrumpResponseScore(play: play, deck: deck, hand: hand);

    return score;
  }
}
