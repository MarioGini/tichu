import 'dart:typed_data';

import 'package:tichu/agents/card_knowledge.dart';
import 'package:tichu/agents/claim_analysis.dart';
import 'package:tichu/agents/hand_shape.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/scoring/score_data.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

export 'package:tichu/agents/card_knowledge.dart' show cardSlot, faceRank;
export 'package:tichu/agents/hand_shape.dart';

part 'feature_encoder_state.dart';

/// Fixed-size numeric feature vector for neural network input.
///
/// **Authoritative layout lives in `rl/schema/feature_spec.json` (v7).**
/// `test/agents/feature_layout_test.dart` asserts the constants below match
/// the spec; edit the spec first, then this file.
///
/// State prefix (shared by every legal action of one decision):
///
/// | group          | size | content                                        |
/// |----------------|------|------------------------------------------------|
/// | hand           |  56  | my cards (bitmap)                              |
/// | played         |  56  | cards already out of play this round (bitmap)  |
/// | unseen         |  17  | per-rank count held by the other three players |
/// | trick          |  20  | current trick, winner seat, wish               |
/// | seats          |  27  | left / partner / right: counts, calls, finish  |
/// | self           |  15  | own calls, round + match score context         |
/// | hand_structure |  10  | combinatorial shape of my hand                 |
/// | history        |  66  | per other player: cards played, passes         |
/// | turn           |   1  | deciding out of turn (interrupting bomb)       |
/// | claim          |   3  | safe-finish analysis of my hand (v7)           |
/// | received       |  51  | schupf card received per sender, by rank (v7)  |
///
/// Action suffix (one per legal action): type, strength, which cards it
/// uses, whether it can be beaten by unseen cards, and the shape of the hand
/// that remains after playing it (the first [legacyActionFeatureCount]
/// features, the layout up to v6), then the claim analysis of that hand
/// (v7).
///
/// Everything here is public information from the acting player's point of
/// view. "Played" and "unseen" are derived as the complement of all hands in
/// the snapshot, which equals the publicly visible set of played cards. This
/// requires a full-information [GameSnapshot] (local engine / headless) in the
/// play phase; in other phases both groups are zero.

const int handFeatureCount = 56;
const int playedFeatureCount = 56;
const int unseenFeatureCount = 17;
const int trickFeatureCount = 20;
const int seatsFeatureCount = 27;
const int selfFeatureCount = 15;
const int handStructureFeatureCount = 10;
const int historyFeatureCount = 66;
const int turnFeatureCount = 1;
const int claimFeatureCount = 3;
const int receivedRankFeatureCount = 51;
const int actionFeatureCount = 54;

/// Action features of the layouts up to v6; v7 appends the claim analysis
/// of the hand after the action, so these are a prefix of the action part.
const int legacyActionFeatureCount = 51;

const int handOffset = 0;
const int playedOffset = handOffset + handFeatureCount; // 56
const int unseenOffset = playedOffset + playedFeatureCount; // 112
const int trickOffset = unseenOffset + unseenFeatureCount; // 129
const int seatsOffset = trickOffset + trickFeatureCount; // 149
const int selfOffset = seatsOffset + seatsFeatureCount; // 176
const int handStructureOffset = selfOffset + selfFeatureCount; // 191
const int historyOffset =
    handStructureOffset + handStructureFeatureCount; // 201
const int turnOffset = historyOffset + historyFeatureCount; // 267
const int claimOffset = turnOffset + turnFeatureCount; // 268
const int receivedOffset = claimOffset + claimFeatureCount; // 271
const int actionOffset = receivedOffset + receivedRankFeatureCount; // 322

/// Offset of the after-action claim features within the action part.
const int actionClaimOffset = legacyActionFeatureCount; // 51

/// Length of the per-decision state prefix (all groups before `action`).
const int stateFeatureCount = actionOffset;
const int totalFeatureCount = stateFeatureCount + actionFeatureCount; // 376

/// Layout before the `claim` and `received` groups (schema v6): state prefix
/// up to `turn`, the first [legacyActionFeatureCount] action features.
const int v6StateFeatureCount = claimOffset; // 268
const int v6TotalFeatureCount =
    v6StateFeatureCount + legacyActionFeatureCount; // 319

/// Layout before the `turn` group (schema v5, e.g. the v5-v7 play
/// policies): they read the first [v5StateFeatureCount] state features and
/// cannot tell an out-of-turn decision from a normal one.
const int v5StateFeatureCount = turnOffset; // 267
const int v5TotalFeatureCount =
    v5StateFeatureCount + legacyActionFeatureCount; // 318

/// Layout before the `history` group (schema v4, e.g. the v3 / v4 play
/// policies): the state prefix stopped at [historyOffset]. Such nets still
/// work; they read the first [legacyStateFeatureCount] state features.
const int legacyStateFeatureCount = historyOffset; // 201
const int legacyTotalFeatureCount =
    legacyStateFeatureCount + legacyActionFeatureCount; // 252

/// The input layout of a play net by its input size: how many state
/// features (a prefix of the current state part) and action features (a
/// prefix of the current action part) it reads; null for an unknown size.
({int state, int action})? playNetLayout(final int inputSize) =>
    switch (inputSize) {
      totalFeatureCount => (
        state: stateFeatureCount,
        action: actionFeatureCount,
      ),
      v6TotalFeatureCount => (
        state: v6StateFeatureCount,
        action: legacyActionFeatureCount,
      ),
      v5TotalFeatureCount => (
        state: v5StateFeatureCount,
        action: legacyActionFeatureCount,
      ),
      legacyTotalFeatureCount => (
        state: legacyStateFeatureCount,
        action: legacyActionFeatureCount,
      ),
      _ => null,
    };

/// Encode the state prefix for [playerId].
List<double> encodeStateFeatures({
  required final GameSnapshot snapshot,
  required final String playerId,
}) => FeatureEncoder(snapshot: snapshot, playerId: playerId).stateFeatures;

/// Per-decision feature encoder. Analyses the snapshot once; state features
/// are computed lazily and cached, action features are computed per call.
class FeatureEncoder {
  final GameSnapshot snapshot;
  final String playerId;

  final int _mySeat;
  final List<Card> _hand;

  /// Slots (0..55) of the cards in my hand.
  final List<int> _handSlots;

  /// Shared, cached card knowledge (played / unseen cards).
  final CardKnowledge _k;

  late final HandShape _handShape = HandShape.fromSlots(_handSlots);

  /// Whether to compute the claim features (state `claim` group and the
  /// after-action claim features). Nets of older layouts do not read them;
  /// then they stay zero and cost nothing.
  final bool claims;

  late final ClaimSolver _claimSolver = ClaimSolver.of(_k);

  /// Claim analysis of my current hand (its score is also the after-pass
  /// value), see [ClaimResult.fromScore].
  late final ClaimHand _claimHand = _claimSolver.hand(_handSlots);
  int get _handClaim => _claimHand.score;

  FeatureEncoder({
    required this.snapshot,
    required this.playerId,
    this.claims = true,
  }) : _mySeat = _seatOf(snapshot, playerId),
       _hand = snapshot.hands[playerId] ?? const <Card>[],
       _handSlots = _slotsOf(snapshot.hands[playerId] ?? const <Card>[]),
       _k = CardKnowledge.of(snapshot, playerId);

  // ── State ────────────────────────────────────────────────────────────────

  late final Float64List stateFeatures = _encodeState();

  // ── Action ───────────────────────────────────────────────────────────────

  /// Encode one action. [play] is ignored when [isPass] is true.
  Float64List actionFeatures(
    final TichuTurn play, {
    final bool isPass = false,
  }) {
    final f = Float64List(actionFeatureCount);
    writeActionFeatures(play, f, 0, isPass: isPass);
    return f;
  }

  /// Write the action features of [play] into [out] starting at [offset].
  /// Lets hot paths reuse one buffer (state prefix + action suffix).
  void writeActionFeatures(
    final TichuTurn play,
    final Float64List out,
    final int offset, {
    final bool isPass = false,
  }) {
    for (var i = 0; i < actionFeatureCount; i++) {
      out[offset + i] = 0.0;
    }
    final pass = isPass || play.type == TurnType.none || play.cards.isEmpty;
    if (pass) {
      out[offset + 0] = 1.0;
      out[offset + 40] = _hand.length / 14.0;
      _handShape.writeTo(out, offset + 41);
      if (claims) {
        ClaimResult.writeScore(_handClaim, out, offset + actionClaimOffset);
      }
      return;
    }

    final deck = snapshot.deck;
    final lead = _isLead(deck);
    final isDog =
        play.cards.length == 1 && play.cards.first.face == CardFace.dog;
    switch (play.type) {
      case TurnType.single:
        out[offset + (isDog ? 8 : 1)] = 1.0;
      case TurnType.pair:
        out[offset + 2] = 1.0;
      case TurnType.triplet:
        out[offset + 3] = 1.0;
      case TurnType.fullHouse:
        out[offset + 4] = 1.0;
      case TurnType.straight:
        out[offset + 5] = 1.0;
      case TurnType.pairStraight:
        out[offset + 6] = 1.0;
      case TurnType.bomb:
        out[offset + 7] = 1.0;
      case TurnType.dog:
        out[offset + 8] = 1.0;
      case TurnType.none || TurnType.empty:
        break;
    }

    out[offset + 9] = (play.value / 25.0).clamp(-1.0, 1.0);
    out[offset + 10] = play.cards.length / 14.0;
    if (!lead) {
      out[offset + 11] = ((play.value - deck.turn.value) / 25.0).clamp(
        -1.0,
        1.0,
      );
    }

    var maxRank = 0.0;
    var minRank = double.infinity;
    // Bit masks over card slots 0..31 / 32..55: two masks because ints are
    // 32-bit for bitwise operations on the web (dart2js).
    var playedLo = 0;
    var playedHi = 0;
    for (final card in play.cards) {
      final slot = cardSlot(card);
      if (slot >= 32) {
        playedHi |= 1 << (slot - 32);
      } else if (slot >= 0) {
        playedLo |= 1 << slot;
      }
      final hist = _histIndex(card);
      if (hist >= 0) {
        out[offset + 23 + hist] += hist < 13 ? 0.25 : 1.0;
      }
      final r = _effectiveRank(card);
      if (r > maxRank) maxRank = r;
      if (r < minRank) minRank = r;
      switch (card.face) {
        case CardFace.phoenix:
          out[offset + 12] = 1.0;
        case CardFace.dragon:
          out[offset + 13] = 1.0;
        case CardFace.mahJong:
          out[offset + 14] = 1.0;
        case CardFace.two ||
            CardFace.three ||
            CardFace.four ||
            CardFace.five ||
            CardFace.six ||
            CardFace.seven ||
            CardFace.eight ||
            CardFace.nine ||
            CardFace.ten ||
            CardFace.jack ||
            CardFace.queen ||
            CardFace.king ||
            CardFace.ace ||
            CardFace.dog ||
            CardFace.none:
          break;
      }
    }
    out[offset + 15] = maxRank / 15.0;
    out[offset + 16] = (minRank.isFinite ? minRank : 0.0) / 15.0;
    out[offset + 17] = (pointsForCards(play.cards) / 25.0).clamp(-1.0, 1.0);

    if (!lead && deck.currentWinner.isNotEmpty) {
      out[offset + 18] = _relativeSeat(deck.currentWinner) == 2 ? 1.0 : 0.0;
    }
    final wish = snapshot.activeWish;
    if (wish != CardFace.none && play.cards.any((final c) => c.face == wish)) {
      out[offset + 19] = 1.0;
    }

    final remaining = <int>[
      for (final slot in _handSlots)
        if ((slot >= 32
                ? playedHi & (1 << (slot - 32))
                : playedLo & (1 << slot)) ==
            0)
          slot,
    ];
    out[offset + 20] = remaining.isEmpty ? 1.0 : 0.0;

    // Bombs are ignored on purpose: the bomb threat always exists and is
    // rare, so "unbeatable" means no non-bomb play can beat it.
    out[offset + 21] = _k.isUnbeatable(play) ? 1.0 : 0.0;

    final after = HandShape.fromSlots(remaining);
    if (play.type != TurnType.bomb && after.bombs < _handShape.bombs) {
      out[offset + 22] = 1.0;
    }
    out[offset + 40] = remaining.length / 14.0;
    after.writeTo(out, offset + 41);
    if (claims) {
      ClaimResult.writeScore(
        _claimSolver.after(_claimHand, play.cards, remaining),
        out,
        offset + actionClaimOffset,
      );
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  int _relativeSeat(final String otherId) {
    for (final p in snapshot.players) {
      if (p.id == otherId) return (p.seat - _mySeat + 4) % 4;
    }
    return -1;
  }

  GamePlayer? _playerAtSeat(final int seat) {
    for (final p in snapshot.players) {
      if (p.seat == seat) return p;
    }
    return null;
  }
}

bool _isLead(final DeckState deck) =>
    deck.turn.type == TurnType.empty ||
    deck.turn.type == TurnType.none ||
    deck.turn.type == TurnType.dog;

int _seatOf(final GameSnapshot snapshot, final String playerId) {
  for (final p in snapshot.players) {
    if (p.id == playerId) return p.seat;
  }
  return 0;
}

List<int> _slotsOf(final List<Card> cards) => [
  for (final c in cards)
    if (cardSlot(c) >= 0) cardSlot(c),
];

/// Rank used for highest/lowest-rank features. A played phoenix takes its
/// assigned value; dragon = 15, mahjong = 1, dog = 0.
double _effectiveRank(final Card card) => switch (card.face) {
  CardFace.dragon => 15,
  CardFace.dog || CardFace.none => 0,
  CardFace.phoenix => card.value.clamp(0.0, 15.0),
  _ => faceRank(card.face).toDouble(),
};

/// Index into the 17-wide rank histogram (r2..rA, mahjong, dog, phoenix,
/// dragon) or -1.
int _histIndex(final Card card) => switch (card.face) {
  CardFace.mahJong => 13,
  CardFace.dog => 14,
  CardFace.phoenix => 15,
  CardFace.dragon => 16,
  CardFace.none => -1,
  _ => faceRank(card.face) - 2,
};
