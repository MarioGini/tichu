import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/bomb_utils.dart';
import 'package:tichu/game/turn/utils/card_utils.dart';
import 'package:tichu/game/turn/utils/straight_utils.dart';

/// Evaluates a Tichu hand and produces a numeric score used for tichu/grand
/// tichu decisions.
///
/// The score is on a 0–100 scale:
/// - 0–29: weak hand, never call
/// - 30–49: decent hand, risky call
/// - 50–69: strong hand, consider tichu
/// - 70+: excellent hand, consider grand tichu
class HandEvaluator {
  /// Evaluate a full hand (8 or 14 cards). Returns a score 0–100.
  static double evaluate(List<Card> hand) {
    if (hand.isEmpty) return 0;

    var score = 0.0;

    score += _highCardScore(hand);
    score += _bombScore(hand);
    score += _connectivityScore(hand);
    score += _tempoScore(hand);

    return score.clamp(0, 100);
  }

  /// Score for high-value individual cards.
  /// Dragon (15), Phoenix (10), Aces (8 each), Kings (3 each)
  static double _highCardScore(List<Card> hand) {
    var score = 0.0;

    if (hand.any((c) => c.face == CardFace.dragon)) score += 15;
    if (hand.any((c) => c.face == CardFace.phoenix)) score += 10;

    final aces = hand.where((c) => c.face == CardFace.ace).length;
    score += aces * 8;

    final kings = hand.where((c) => c.face == CardFace.king).length;
    score += kings * 3;

    return score;
  }

  /// Score for holding bombs. A bomb is a huge advantage: +15 per bomb.
  static double _bombScore(List<Card> hand) {
    final handCopy = List<Card>.from(hand);
    final bombs = getBombs(handCopy);
    return bombs.length * 15.0;
  }

  /// Score for connected cards (pairs, triplets, straights).
  /// More connected = fewer leads needed = faster out.
  static double _connectivityScore(List<Card> hand) {
    var score = 0.0;
    final handCopy = List<Card>.from(hand);

    // Count pairs and triplets.
    final occurrences = getOccurrenceCount(handCopy);
    for (final entry in occurrences.entries) {
      if (entry.key == CardFace.phoenix ||
          entry.key == CardFace.dog ||
          entry.key == CardFace.dragon) {
        continue;
      }
      if (entry.value >= 3) {
        score += 4; // Triplet is strong
      } else if (entry.value >= 2) {
        score += 2; // Pair is decent
      }
    }

    // Check for straight potential (connected sequences).
    final normalCards = handCopy
        .where(
          (c) =>
              c.face != CardFace.dragon &&
              c.face != CardFace.dog &&
              c.face != CardFace.phoenix,
        )
        .toList();
    final unique = removeDuplicates(List<Card>.from(normalCards));
    if (unique.length >= 5) {
      final connected = findConnectedCards(unique);
      for (final seq in connected) {
        final length = seq.endIdx - seq.beginIdx + 1;
        if (length >= 5) {
          score += 8; // Full straight in hand
        } else if (length >= 4) {
          score += 4; // Near-straight
        } else if (length >= 3) {
          score += 2; // Partial sequence
        }
      }
    }

    return score;
  }

  /// Tempo score: estimate how quickly we can shed cards.
  /// Fewer distinct "groups" means fewer leads needed.
  static double _tempoScore(List<Card> hand) {
    var score = 0.0;
    final cardCount = hand.length;

    if (cardCount == 0) return 0;

    // Dog is bad for tempo (wastes a lead, gives it to partner)
    if (hand.any((c) => c.face == CardFace.dog)) {
      score -= 3;
    }

    // Mah Jong gives first lead advantage
    if (hand.any((c) => c.face == CardFace.mahJong)) {
      score += 3;
    }

    // Fewer cards = closer to winning (for 14-card evaluation baseline)
    // For 8 cards, we scale proportionally.
    final singletons = _countSingletons(hand);
    // Each extra singleton beyond 2 is a penalty (needs a separate lead)
    if (singletons > 2) {
      score -= (singletons - 2) * 2;
    }

    return score;
  }

  /// Count cards that don't pair with anything else in the hand.
  static int _countSingletons(List<Card> hand) {
    final normalCards = hand
        .where(
          (c) =>
              c.face != CardFace.phoenix &&
              c.face != CardFace.dog &&
              c.face != CardFace.dragon,
        )
        .toList();
    final occurrences = getOccurrenceCount(normalCards);
    return occurrences.values.where((v) => v == 1).length;
  }
}
