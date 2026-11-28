import 'dart:math';

import 'package:meta/meta.dart';

import 'package:tichu/agents/card_knowledge.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/round_log.dart';
import 'package:tichu/game/scoring/score_state.dart';
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

/// Where the unseen high cards are, by the partner's promise: how many the
/// partner holds now and how many the two opponents hold together (each
/// as min..max, inclusive).
@immutable
class HighCardRead {
  final int partnerMin;
  final int partnerMax;
  final int opponentsMin;
  final int opponentsMax;

  const HighCardRead({
    required this.partnerMin,
    required this.partnerMax,
    required this.opponentsMin,
    required this.opponentsMax,
  });

  @override
  bool operator ==(Object other) =>
      other is HighCardRead &&
      other.partnerMin == partnerMin &&
      other.partnerMax == partnerMax &&
      other.opponentsMin == opponentsMin &&
      other.opponentsMax == opponentsMax;

  @override
  int get hashCode =>
      Object.hash(partnerMin, partnerMax, opponentsMin, opponentsMax);

  @override
  String toString() =>
      'HighCardRead(partner $partnerMin..$partnerMax, '
      'opponents $opponentsMin..$opponentsMax)';
}

/// What [convention] tells me about the high cards I cannot see; null =
/// nothing (free, no pass yet, the convention was off, or the partner
/// passed a high card while their right opponent had called Grand).
///
/// - [received]: the card the partner passed me; [passedToPartner]: mine.
/// - [partnerPlayed]: every card the partner played this round.
/// - [grandCalled]: my partner or I called Grand Tichu (the convention was
///   off). A plain Tichu call is taken to come after the schupf: no bot
///   calls before it (`shouldCallTichuBeforeSchupf`).
/// - [partnersRightGrand]: my left opponent called Grand Tichu.
/// - [unseenHighCards]: high cards in the other three hands.
/// - [partnerHandSize]: cards the partner still holds.
///
/// The opponents' passes to the partner are taken to hold no high card.
HighCardRead? readPartnerPromise({
  required PartnerConvention convention,
  required Card? received,
  required Card? passedToPartner,
  required List<Card> partnerPlayed,
  required bool grandCalled,
  required bool partnersRightGrand,
  required int unseenHighCards,
  required int partnerHandSize,
}) {
  if (received == null || grandCalled) return null;
  final range = convention.promisedOtherHighCards(
    received,
    partnersRightGrand: partnersRightGrand,
  );
  if (range == null) return null;
  bool same(Card a, Card b) => a.face == b.face && a.color == b.color;
  final mine = passedToPartner != null && isHighCard(passedToPartner)
      ? passedToPartner
      : null;
  final minePlayed = mine != null && partnerPlayed.any((c) => same(c, mine));
  final ownPlayed =
      partnerPlayed.where(isHighCard).length - (minePlayed ? 1 : 0);
  final mineHeld = mine != null && !minePlayed ? 1 : 0;
  final cap = min(unseenHighCards, partnerHandSize);
  final lo = min(max(0, range.$1 - ownPlayed) + mineHeld, cap);
  final hi = max(lo, min(max(0, range.$2 - ownPlayed) + mineHeld, cap));
  return HighCardRead(
    partnerMin: lo,
    partnerMax: hi,
    opponentsMin: unseenHighCards - hi,
    opponentsMax: unseenHighCards - lo,
  );
}

/// [holders] (`holders[slot][k]`, k = 0 left opponent, 1 partner, 2 right
/// opponent, see `BeliefModel`) with a [read] that rules a side out: no
/// high card with the partner, or none with the opponents. The other
/// side's probabilities are renormalised; slots that are not high cards
/// stay as they are.
List<List<double>> applyHighCardRead(
  List<List<double>> holders,
  HighCardRead? read,
) {
  if (read == null || (read.partnerMax > 0 && read.opponentsMax > 0)) {
    return holders;
  }
  final noPartner = read.partnerMax == 0;
  return [
    for (var slot = 0; slot < holders.length; slot++)
      if (!_highCardSlots.contains(slot))
        holders[slot]
      else
        _rule(holders[slot], noPartner),
  ];
}

const Set<int> _highCardSlots = {12, 25, 38, 51, 54, 55};

List<double> _rule(List<double> p, bool noPartner) {
  final q = noPartner ? [p[0], 0.0, p[2]] : [0.0, p[1], 0.0];
  final z = q[0] + q[1] + q[2];
  if (z <= 0) return noPartner ? const [0.5, 0, 0.5] : const [0, 1, 0];
  return [q[0] / z, q[1] / z, q[2] / z];
}

/// Moves high cards between the partner's dealt hand and the opponents'
/// so that the partner's high cards ([partnerKept] now) lie in [range]
/// (see [HighCardRead]). Pinned cards (known positions) are never moved. A
/// range no swap can reach is left as far as it got: the partner did not
/// keep the convention.
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

/// [readPartnerPromise] for [playerId] at a table: its [players], their
/// [hands] (full information: only hand sizes and the high cards outside
/// my hand are used), this round's [roundLog], the completed schupf
/// [selections] and the round's [calls].
HighCardRead? readPartnerPromiseAt({
  required PartnerConvention convention,
  required String playerId,
  required List<GamePlayer> players,
  required Map<String, List<Card>> hands,
  required List<RoundLogEntry> roundLog,
  required Map<String, SchupfAction> selections,
  required Map<String, TichuCall> calls,
}) {
  if (convention == PartnerConvention.free) return null;
  final me = players.firstWhere((p) => p.id == playerId);
  String idAt(int offset) =>
      players.firstWhere((p) => p.seat == (me.seat + offset) % 4).id;
  final partnerId = idAt(2);
  return readPartnerPromise(
    convention: convention,
    received: selections[partnerId]?.toPartner,
    passedToPartner: selections[playerId]?.toPartner,
    partnerPlayed: [
      for (final e in roundLog)
        if (e.playerId == partnerId) ...e.cards,
    ],
    grandCalled:
        calls[playerId] == TichuCall.grandTichu ||
        calls[partnerId] == TichuCall.grandTichu,
    partnersRightGrand: calls[idAt(1)] == TichuCall.grandTichu,
    unseenHighCards: [
      for (final e in hands.entries)
        if (e.key != playerId) ...e.value.where(isHighCard),
    ].length,
    partnerHandSize: hands[partnerId]?.length ?? 0,
  );
}
