import 'package:tichu/game/game_backend.dart';
import 'package:tichu/agents/ai/game_state_tracker.dart';
import 'package:tichu/agents/ai/table_relationships.dart';
import 'package:tichu/game/scoring/score_data.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/card_utils.dart';

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
  });
}

class TurnScorer {
  final PolicyWeights weights;
  final GameStateTracker? tracker;

  const TurnScorer({this.weights = const PolicyWeights(), this.tracker});

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

    final isLeading =
        deck.turn.type == TurnType.empty ||
        deck.turn.type == TurnType.none ||
        deck.turn.type == TurnType.dog;

    final isEarly = hand.length >= 9;
    final trickPoints = isLeading ? 0 : pointsForCards(deck.turn.cards);
    final opponentTichuNearFinish = _opponentTichuNearFinish(
      snapshot,
      playerId,
    );
    final opponentTichuNearFinishWinning = _opponentTichuNearFinishWinningTrick(
      snapshot,
      playerId,
      deck,
    );

    final maxValue = 25.0;
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
        .where((card) => controlCards.contains(card.face))
        .length;
    if (controlCount > 0) {
      score -= weights.controlPreservation * controlCount;
    }

    if (isEarly) {
      final hasLastAce = tracker?.hasLastAce(hand) ?? false;
      final hasLastKing = tracker?.hasLastKing(hand) ?? false;
      final allAcesKnown = tracker?.allAcesKnown ?? false;
      final pointFactor = (trickPoints / 25).clamp(0, 1).toDouble();
      final highCount = play.cards.where((card) {
        if (!highCards.contains(card.face)) return false;
        if (card.face == CardFace.ace && hasLastAce) return false;
        if (card.face == CardFace.king && allAcesKnown && hasLastKing) {
          return false;
        }
        return true;
      }).length;
      if (highCount > 0) {
        score -= weights.avoidHighBurn * highCount * (1 - pointFactor);
      }
    }

    if (!isLeading && trickPoints != 0) {
      score += weights.trickPointCapture * trickPoints;
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

    if (_opponentLow(snapshot, playerId) && _isUnbeatableLine(play)) {
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
        if (play.cards.length >= 2 || _isUnbeatableLine(play)) {
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

    final partnerId = TableRelationships(snapshot, playerId).partnerId;
    if (_partnerCalledTichu(snapshot, playerId) &&
        snapshot.lastPlayedBy == partnerId &&
        deck.turn.type != TurnType.empty &&
        deck.turn.type != TurnType.none) {
      score -= weights.supportPartnerTichu;
    }

    return score;
  }

  bool _opponentLow(GameSnapshot snapshot, String playerId) {
    final table = TableRelationships(snapshot, playerId);
    for (final player in table.opponents) {
      final count = (snapshot.hands[player.id] ?? const <Card>[]).length;
      if (count > 0 && count < 5) {
        return true;
      }
    }
    return false;
  }

  bool _opponentAtOne(GameSnapshot snapshot, String playerId) {
    final table = TableRelationships(snapshot, playerId);
    for (final player in table.opponents) {
      final count = (snapshot.hands[player.id] ?? const <Card>[]).length;
      if (count == 1) {
        return true;
      }
    }
    return false;
  }

  bool _opponentTichuNearFinish(GameSnapshot snapshot, String playerId) {
    final table = TableRelationships(snapshot, playerId);
    for (final player in table.opponents) {
      final call = snapshot.scoreState.tichuCalls[player.id] ?? TichuCall.none;
      if (call == TichuCall.none) continue;
      final count = (snapshot.hands[player.id] ?? const <Card>[]).length;
      if (count > 0 && count <= 2) {
        return true;
      }
    }
    return false;
  }

  bool _opponentTichuNearFinishWinningTrick(
    GameSnapshot snapshot,
    String playerId,
    DeckState deck,
  ) {
    final table = TableRelationships(snapshot, playerId);
    final winnerId = deck.currentWinner.isNotEmpty
        ? deck.currentWinner
        : snapshot.lastPlayedBy;
    if (winnerId == null) {
      return false;
    }

    if (!table.isOpponent(winnerId)) {
      return false;
    }

    final call = snapshot.scoreState.tichuCalls[winnerId] ?? TichuCall.none;
    if (call == TichuCall.none) {
      return false;
    }
    final count = (snapshot.hands[winnerId] ?? const <Card>[]).length;
    return count > 0 && count <= 2;
  }

  bool _partnerCalledTichu(GameSnapshot snapshot, String playerId) {
    final partnerId = TableRelationships(snapshot, playerId).partnerId!;
    final call = snapshot.scoreState.tichuCalls[partnerId] ?? TichuCall.none;
    return call != TichuCall.none;
  }

  bool _opponentCalledTichu(GameSnapshot snapshot, String playerId) {
    final table = TableRelationships(snapshot, playerId);
    for (final player in table.opponents) {
      final call = snapshot.scoreState.tichuCalls[player.id] ?? TichuCall.none;
      if (call != TichuCall.none) {
        return true;
      }
    }
    return false;
  }

  bool _isUnbeatableLine(TichuTurn play) {
    return play.type == TurnType.straight ||
        play.type == TurnType.pairStraight ||
        play.type == TurnType.fullHouse ||
        play.type == TurnType.bomb;
  }

  int _countLowSingletons(List<Card> hand) {
    final normalCards = hand
        .where(
          (c) =>
              c.face != CardFace.phoenix &&
              c.face != CardFace.dog &&
              c.face != CardFace.dragon,
        )
        .toList();
    final occurrences = getOccurrenceCount(normalCards);
    var count = 0;
    for (final entry in occurrences.entries) {
      if (entry.value != 1) continue;
      final value = Card.getValue(entry.key);
      if (value <= 7) {
        count += 1;
      }
    }
    return count;
  }

  List<Card> _removePlayedCards(List<Card> hand, List<Card> played) {
    final remaining = List<Card>.from(hand);
    for (final card in played) {
      if (card.face == CardFace.phoenix) {
        final index = remaining.indexWhere((c) => c.face == CardFace.phoenix);
        if (index != -1) {
          remaining.removeAt(index);
        }
        continue;
      }
      final index = remaining.indexWhere((c) => c == card);
      if (index != -1) {
        remaining.removeAt(index);
      }
    }
    return remaining;
  }
}
