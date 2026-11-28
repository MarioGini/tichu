import 'package:tichu/game/scoring/score_state.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// What the card passed to the partner promises about the passer's high
/// cards (Aces, Phoenix, Dragon) under a [PartnerConvention].
enum HighCardPromise {
  /// No promise (no convention, or it is off).
  none,

  /// No high card left in the passer's hand after the schupf.
  zero,

  /// At least two high cards in the passer's hand after the schupf.
  twoOrMore,

  /// At most one high card in the passer's hand after the schupf.
  atMostOne,
}

/// A partner-passing convention: the card passed to the partner signals the
/// passer's high-card count, and the partner's search deals only worlds
/// that keep the promise.
///
/// From tichuengine.com, whose bots follow such conventions and make
/// inferences from them ("2+HC Odd", the site author's own convention):
///
/// - with 2 or more high cards, pass an odd card (3, 5, 7, 9, J, K, the Mah
///   Jong or the Dog);
/// - with none, pass an even card (2, 4, 6, 8, 10, Q);
/// - with exactly one, pass that high card.
///
/// It is off while someone of the passer's team has called Grand Tichu
/// (the Grand caller is given a high card if possible instead).
/// [conforms] judges a candidate pass; [promise] reads one.
///
/// [parity] is a lighter variant that never forces a high card to the
/// partner: an odd card promises 2 or more high cards, an even card at
/// most one (2+HC Odd lost 43.5 % without retrained nets, largely by
/// handing over a lone Ace or Dragon).
enum PartnerConvention {
  none,
  twoHighCardsOdd,
  parity;

  /// The convention named [name] (`none`, `2hc-odd`), or null.
  static PartnerConvention? tryParse(String name) => switch (name) {
    'none' => none,
    '2hc-odd' => twoHighCardsOdd,
    'parity' => parity,
    _ => null,
  };

  /// Aces, Phoenix and Dragon.
  static bool isHighCard(Card card) =>
      card.face == CardFace.ace ||
      card.face == CardFace.phoenix ||
      card.face == CardFace.dragon;

  static int highCards(Iterable<Card> cards) => cards.where(isHighCard).length;

  /// Odd in the convention's sense: 3, 5, 7, 9, J, K, Mah Jong, Dog.
  static bool isOdd(Card card) => switch (card.face) {
    CardFace.mahJong || CardFace.dog => true,
    CardFace.three ||
    CardFace.five ||
    CardFace.seven ||
    CardFace.nine ||
    CardFace.jack ||
    CardFace.king => true,
    CardFace.none ||
    CardFace.two ||
    CardFace.four ||
    CardFace.six ||
    CardFace.eight ||
    CardFace.ten ||
    CardFace.queen ||
    CardFace.ace ||
    CardFace.dragon ||
    CardFace.phoenix => false,
  };

  /// Whether the convention applies to a pass by a player whose team calls
  /// are [ownCall] and [partnerCall].
  bool appliesTo(TichuCall ownCall, TichuCall partnerCall) =>
      this != none &&
      ownCall != TichuCall.grandTichu &&
      partnerCall != TichuCall.grandTichu;

  /// Whether passing [toPartner] (and [toOpponents]) from the 14-card
  /// [hand] keeps the convention (always true without one). The promise is
  /// about the high cards the passer keeps, so high cards passed to the
  /// opponents do not count.
  bool conforms(
    List<Card> hand,
    Card toPartner, {
    List<Card> toOpponents = const [],
  }) {
    if (this == none) return true;
    final high = highCards(hand) - highCards(toOpponents);
    if (this == parity) {
      return !isHighCard(toPartner) && isOdd(toPartner) == (high >= 2);
    }
    if (high == 0) return !isHighCard(toPartner) && !isOdd(toPartner);
    if (high == 1) return isHighCard(toPartner);
    return !isHighCard(toPartner) && isOdd(toPartner);
  }

  /// What receiving [fromPartner] promises about the partner's high cards
  /// after the schupf.
  HighCardPromise promise(Card fromPartner) {
    if (this == none) return HighCardPromise.none;
    if (this == parity) {
      if (isHighCard(fromPartner)) return HighCardPromise.none;
      return isOdd(fromPartner)
          ? HighCardPromise.twoOrMore
          : HighCardPromise.atMostOne;
    }
    if (isHighCard(fromPartner)) return HighCardPromise.zero;
    return isOdd(fromPartner)
        ? HighCardPromise.twoOrMore
        : HighCardPromise.zero;
  }

  /// Whether [highCardsSeen] high cards (a lower bound of those kept) can
  /// still keep [promise].
  static bool keepsSoFar(HighCardPromise promise, int highCardsSeen) =>
      switch (promise) {
        HighCardPromise.none || HighCardPromise.twoOrMore => true,
        HighCardPromise.zero => highCardsSeen == 0,
        HighCardPromise.atMostOne => highCardsSeen <= 1,
      };

  /// Whether a partner who kept [highCardsKept] high cards in the schupf
  /// keeps [promise].
  static bool keeps(HighCardPromise promise, int highCardsKept) =>
      switch (promise) {
        HighCardPromise.none => true,
        HighCardPromise.zero => highCardsKept == 0,
        HighCardPromise.twoOrMore => highCardsKept >= 2,
        HighCardPromise.atMostOne => highCardsKept <= 1,
      };
}
