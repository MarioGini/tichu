import 'dart:math';

import 'package:tichu/agents/card_knowledge.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// What the card passed to the partner in the schupf says about the rest of
/// the passer's hand.
///
/// [twoHcOdd] is "2+ HC Odd" (tichuengine.com/about, "Partner-Passing
/// Conventions"). High cards (HC) are Aces, the Phoenix and the Dragon;
/// they are counted in the 14-card hand before passing:
/// - 1 HC: pass that card.
/// - 2+ HC: pass an odd card (3, 5, 7, 9, J, K), the Mahjong or the Dog.
/// - 0 HC: pass an even card (2, 4, 6, 8, 10, Q).
/// - My partner or I called (Grand) Tichu before the schupf: the
///   convention is off; a calling partner gets a high card if I have one.
/// - My right opponent called Grand Tichu: with 1+ HC I may pass an odd
///   card or a high card.
///
/// [free] is no convention (the learned schupf picks the partner card).
enum PartnerConvention { free, twoHcOdd }

/// Ace, Phoenix or Dragon.
bool isHighCard(Card c) =>
    c.face == CardFace.ace ||
    c.face == CardFace.phoenix ||
    c.face == CardFace.dragon;

/// The "odd" partner cards of [PartnerConvention.twoHcOdd]: odd normal
/// ranks, the Mahjong and the Dog.
bool isOddSignal(Card c) => switch (c.face) {
  CardFace.mahJong || CardFace.dog => true,
  CardFace.ace || CardFace.phoenix || CardFace.dragon || CardFace.none => false,
  _ => faceRank(c.face).isOdd,
};

/// Even normal ranks (2 .. Q).
bool isEvenSignal(Card c) => switch (c.face) {
  CardFace.mahJong ||
  CardFace.dog ||
  CardFace.ace ||
  CardFace.phoenix ||
  CardFace.dragon ||
  CardFace.none => false,
  _ => faceRank(c.face).isEven,
};

/// Strength order for passing: Dog 0, Mahjong 1, 2..A, Phoenix 15,
/// Dragon 16 (`Card.value` puts the Phoenix below the Dog).
int cardStrength(Card c) => switch (c.face) {
  CardFace.dog => 0,
  CardFace.mahJong => 1,
  CardFace.phoenix => 15,
  CardFace.dragon => 16,
  _ => faceRank(c.face),
};

/// High cards in total: four Aces, the Phoenix and the Dragon.
const int highCardsInDeck = 6;

extension PartnerConventionRules on PartnerConvention {
  /// Indices of [hand] (the full hand before passing) this convention lets
  /// me pass to the partner; null when it does not constrain the pass.
  ///
  /// [selfCalled] / [partnerCalled]: a (Grand) Tichu call before the
  /// schupf. [rightGrand]: my right opponent called Grand Tichu.
  /// Null too when no card of the hand fits (the passer then cannot keep
  /// the promise, and the receiver's worlds drop it, see
  /// [promisedOtherHighCards]).
  Set<int>? allowedPartnerCards(
    List<Card> hand, {
    required bool selfCalled,
    required bool partnerCalled,
    required bool rightGrand,
  }) {
    if (this == PartnerConvention.free) return null;
    Set<int>? where(bool Function(Card) test) {
      final s = {
        for (var i = 0; i < hand.length; i++)
          if (test(hand[i])) i,
      };
      return s.isEmpty ? null : s;
    }

    if (partnerCalled) return where(isHighCard);
    if (selfCalled) return null;
    final highCards = hand.where(isHighCard).length;
    if (highCards == 0) return where(isEvenSignal);
    if (rightGrand) return where((c) => isHighCard(c) || isOddSignal(c));
    if (highCards == 1) return where(isHighCard);
    return where(isOddSignal);
  }

  /// The high cards the partner kept (besides [received], the card they
  /// passed me), as (min, max) of their 14-card hand before passing; null
  /// = no information.
  ///
  /// [partnersRightGrand]: my left opponent (the partner's right one)
  /// called Grand Tichu. The caller decides whether the convention was on
  /// (no call by me or the partner before the schupf).
  (int, int)? promisedOtherHighCards(
    Card received, {
    required bool partnersRightGrand,
  }) {
    if (this == PartnerConvention.free) return null;
    if (isHighCard(received)) return partnersRightGrand ? null : (0, 0);
    if (isOddSignal(received)) {
      return (partnersRightGrand ? 1 : 2, highCardsInDeck);
    }
    return (0, 0);
  }
}

/// Moves high cards between the partner's dealt hand and the opponents'
/// so that [partnerKept] — high cards the partner held before the schupf
/// besides the one they passed — lies in [range]. Pinned cards (known
/// positions) are never moved. A promise no swap can meet is left as far
/// as it got: the partner did not keep the convention.
///
/// `partnerKept` = high cards in the partner's dealt hand + those the
/// partner already played - those I passed the partner (the opponents'
/// passes to the partner are unknown and taken to hold none).
void enforceHighCardPromise(
  Map<String, List<Card>> deal, {
  required String partnerId,
  required List<String> opponentIds,
  required int partnerKept,
  required (int, int) range,
  required bool Function(Card) isPinned,
  required Random random,
}) {
  final partner = deal[partnerId];
  if (partner == null) return;
  var kept = partnerKept;
  List<int> movable(List<Card> hand, bool high) => [
    for (var i = 0; i < hand.length; i++)
      if (isHighCard(hand[i]) == high && !isPinned(hand[i])) i,
  ];
  // Every (opponent, index) of a movable card with high-card status [high].
  List<(String, int)> opponentCards(bool high) => [
    for (final id in opponentIds)
      if (deal[id] != null)
        for (final i in movable(deal[id]!, high)) (id, i),
  ];
  void swap(int pi, (String, int) other) {
    final (id, oi) = other;
    final hand = deal[id]!;
    final c = partner[pi];
    partner[pi] = hand[oi];
    hand[oi] = c;
  }

  while (kept > range.$2) {
    final mine = movable(partner, true);
    final theirs = opponentCards(false);
    if (mine.isEmpty || theirs.isEmpty) return;
    swap(
      mine[random.nextInt(mine.length)],
      theirs[random.nextInt(theirs.length)],
    );
    kept--;
  }
  while (kept < range.$1) {
    final mine = movable(partner, false);
    final theirs = opponentCards(true);
    if (mine.isEmpty || theirs.isEmpty) return;
    swap(
      mine[random.nextInt(mine.length)],
      theirs[random.nextInt(theirs.length)],
    );
    kept++;
  }
}
