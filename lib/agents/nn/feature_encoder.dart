import 'package:tichu/agents/card_knowledge.dart';
import 'package:tichu/agents/hand_shape.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/scoring/score_data.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

export 'package:tichu/agents/card_knowledge.dart' show cardSlot, faceRank;
export 'package:tichu/agents/hand_shape.dart';

/// Fixed-size numeric feature vector for neural network input.
///
/// **Authoritative layout lives in `rl/schema/feature_spec.json` (v4).**
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
///
/// Action suffix (one per legal action): type, strength, which cards it
/// uses, whether it can be beaten by unseen cards, and the shape of the hand
/// that remains after playing it.
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
const int actionFeatureCount = 51;

const int handOffset = 0;
const int playedOffset = handOffset + handFeatureCount; // 56
const int unseenOffset = playedOffset + playedFeatureCount; // 112
const int trickOffset = unseenOffset + unseenFeatureCount; // 129
const int seatsOffset = trickOffset + trickFeatureCount; // 149
const int selfOffset = seatsOffset + seatsFeatureCount; // 176
const int handStructureOffset = selfOffset + selfFeatureCount; // 191
const int actionOffset = handStructureOffset + handStructureFeatureCount; // 201

/// Length of the per-decision state prefix (all groups before `action`).
const int stateFeatureCount = actionOffset;
const int totalFeatureCount = stateFeatureCount + actionFeatureCount; // 252

/// Encode the state prefix for [playerId].
List<double> encodeStateFeatures({
  required final GameSnapshot snapshot,
  required final String playerId,
}) => FeatureEncoder(snapshot: snapshot, playerId: playerId).stateFeatures;

/// Encode one legal action (or pass) for [playerId] in [snapshot].
///
/// When encoding many actions for the same decision, build one
/// [FeatureEncoder] and call [FeatureEncoder.actionFeatures] instead; it
/// caches the hand/unseen analysis.
List<double> encodeActionFeatures({
  required final GameSnapshot snapshot,
  required final String playerId,
  required final TichuTurn play,
  final bool isPass = false,
}) => FeatureEncoder(
  snapshot: snapshot,
  playerId: playerId,
).actionFeatures(play, isPass: isPass);

/// Combine state + action features into a single input vector.
List<double> encodeStateActionFeatures({
  required final GameSnapshot snapshot,
  required final String playerId,
  required final TichuTurn play,
  final bool isPass = false,
}) {
  final encoder = FeatureEncoder(snapshot: snapshot, playerId: playerId);
  return [
    ...encoder.stateFeatures,
    ...encoder.actionFeatures(play, isPass: isPass),
  ];
}

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

  FeatureEncoder({required this.snapshot, required this.playerId})
    : _mySeat = _seatOf(snapshot, playerId),
      _hand = snapshot.hands[playerId] ?? const <Card>[],
      _handSlots = _slotsOf(snapshot.hands[playerId] ?? const <Card>[]),
      _k = CardKnowledge.of(snapshot, playerId);

  // ── State ────────────────────────────────────────────────────────────────

  late final List<double> stateFeatures = _encodeState();

  List<double> _encodeState() {
    final f = List<double>.filled(stateFeatureCount, 0);

    // hand / played bitmaps.
    for (final slot in _handSlots) {
      f[handOffset + slot] = 1.0;
    }
    for (var slot = 0; slot < CardKnowledge.slotCount; slot++) {
      if (_k.isSlotPlayed(slot)) f[playedOffset + slot] = 1.0;
    }

    // unseen per rank.
    const rankFaces = [
      CardFace.two,
      CardFace.three,
      CardFace.four,
      CardFace.five,
      CardFace.six,
      CardFace.seven,
      CardFace.eight,
      CardFace.nine,
      CardFace.ten,
      CardFace.jack,
      CardFace.queen,
      CardFace.king,
      CardFace.ace,
    ];
    for (var i = 0; i < rankFaces.length; i++) {
      f[unseenOffset + i] = _k.unseenCount(rankFaces[i]) / 4.0;
    }
    f[unseenOffset + 13] = _k.unseenCount(CardFace.mahJong).toDouble();
    f[unseenOffset + 14] = _k.dogUnseen ? 1.0 : 0.0;
    f[unseenOffset + 15] = _k.phoenixUnseen ? 1.0 : 0.0;
    f[unseenOffset + 16] = _k.dragonUnseen ? 1.0 : 0.0;

    _encodeTrick(f);
    _encodeSeats(f);
    _encodeSelf(f);
    _handShape.writeTo(f, handStructureOffset);
    return f;
  }

  void _encodeTrick(final List<double> f) {
    final deck = snapshot.deck;
    final turn = deck.turn;
    const o = trickOffset;
    if (_isLead(deck)) {
      f[o + 0] = 1.0;
    } else {
      switch (turn.type) {
        case TurnType.single:
          f[o + 1] = 1.0;
        case TurnType.pair:
          f[o + 2] = 1.0;
        case TurnType.triplet:
          f[o + 3] = 1.0;
        case TurnType.fullHouse:
          f[o + 4] = 1.0;
        case TurnType.straight:
          f[o + 5] = 1.0;
        case TurnType.pairStraight:
          f[o + 6] = 1.0;
        case TurnType.bomb:
          f[o + 7] = 1.0;
        case TurnType.none || TurnType.empty || TurnType.dog:
          break;
      }
      f[o + 8] = (turn.value / 25.0).clamp(-1.0, 1.0);
      f[o + 9] = turn.cards.length / 14.0;
      f[o + 19] =
          turn.type == TurnType.single &&
              turn.cards.any((final c) => c.face == CardFace.dragon)
          ? 1.0
          : 0.0;
    }
    f[o + 10] = (snapshot.trickPoints / 50.0).clamp(-1.0, 1.0);

    final winner = deck.currentWinner;
    if (winner.isNotEmpty) {
      final rel = _relativeSeat(winner);
      if (rel >= 0) f[o + 11 + rel] = 1.0;
    }
    f[o + 15] = (snapshot.consecutivePasses / 3.0).clamp(0.0, 1.0);

    final wish = snapshot.activeWish;
    if (wish != CardFace.none) {
      f[o + 16] = 1.0;
      f[o + 17] = faceRank(wish) / 14.0;
      f[o + 18] = _hand.any((final c) => c.face == wish) ? 1.0 : 0.0;
    }
  }

  void _encodeSeats(final List<double> f) {
    final score = snapshot.scoreState;
    final finishOrder = score.finishOrder;
    for (var rel = 1; rel <= 3; rel++) {
      final o = seatsOffset + (rel - 1) * 9;
      final player = _playerAtSeat((_mySeat + rel) % 4);
      if (player == null) continue;
      final id = player.id;
      final count = snapshot.hands[id]?.length ?? 0;
      f[o + 0] = count / 14.0;
      f[o + 1] = count == 1 ? 1.0 : 0.0;
      f[o + 2] = count > 0 && count <= 3 ? 1.0 : 0.0;
      f[o + 3] = finishOrder.contains(id) ? 1.0 : 0.0;
      f[o + 4] = finishOrder.isNotEmpty && finishOrder.first == id ? 1.0 : 0.0;
      final call = score.tichuCalls[id] ?? TichuCall.none;
      f[o + 5] = call == TichuCall.tichu ? 1.0 : 0.0;
      f[o + 6] = call == TichuCall.grandTichu ? 1.0 : 0.0;
      f[o + 7] = ((score.playerRoundPoints[id] ?? 0) / 100.0).clamp(-1.0, 1.0);
      f[o + 8] = _knownPassedHeld(id) / 3.0;
    }
  }

  /// Cards I schupfed to [otherId] that have not been played yet — these are
  /// known to still be in that player's hand.
  int _knownPassedHeld(final String otherId) {
    final receipts =
        snapshot.schupfReceipts[otherId] ?? const <SchupfReceipt>[];
    var held = 0;
    for (final r in receipts) {
      if (r.fromPlayerId != playerId) continue;
      if (_k.isUnseen(r.card)) held++;
    }
    return held;
  }

  void _encodeSelf(final List<double> f) {
    const o = selfOffset;
    final score = snapshot.scoreState;
    final myCall = score.tichuCalls[playerId] ?? TichuCall.none;
    f[o + 0] = _hand.length / 14.0;
    f[o + 1] = myCall == TichuCall.tichu ? 1.0 : 0.0;
    f[o + 2] = myCall == TichuCall.grandTichu ? 1.0 : 0.0;
    f[o + 3] = (snapshot.canCallTichuByPlayer[playerId] ?? false) ? 1.0 : 0.0;
    f[o + 4] = ((score.playerRoundPoints[playerId] ?? 0) / 100.0).clamp(
      -1.0,
      1.0,
    );
    f[o + 5] = score.finishOrder.length / 4.0;
    if (score.finishOrder.isNotEmpty) {
      final first = _relativeSeat(score.finishOrder.first);
      if (first == 0 || first == 2) {
        f[o + 6] = 1.0;
      } else if (first == 1 || first == 3) {
        f[o + 7] = 1.0;
      }
    }
    f[o + 8] = _handShape.bombs > 0 ? 1.0 : 0.0;

    final myTeam = _mySeat.isEven ? 0 : 1;
    final ownRound = myTeam == 0 ? score.teamOneRound : score.teamTwoRound;
    final oppRound = myTeam == 0 ? score.teamTwoRound : score.teamOneRound;
    final ownTotal = myTeam == 0 ? score.teamOneTotal : score.teamTwoTotal;
    final oppTotal = myTeam == 0 ? score.teamTwoTotal : score.teamOneTotal;
    f[o + 9] = (ownRound / 100.0).clamp(-1.0, 1.0);
    f[o + 10] = (oppRound / 100.0).clamp(-1.0, 1.0);
    f[o + 11] = ((ownTotal + ownRound - oppTotal - oppRound) / 500.0).clamp(
      -1.0,
      1.0,
    );
    final target = score.targetScore > 0 ? score.targetScore : 1000;
    f[o + 12] = ((target - ownTotal) / target).clamp(0.0, 1.0);
    f[o + 13] = ((target - oppTotal) / target).clamp(0.0, 1.0);
    f[o + 14] = _k.unseenBombPossible ? 1.0 : 0.0;
  }

  // ── Action ───────────────────────────────────────────────────────────────

  /// Encode one action. [play] is ignored when [isPass] is true.
  List<double> actionFeatures(
    final TichuTurn play, {
    final bool isPass = false,
  }) {
    final f = List<double>.filled(actionFeatureCount, 0);
    writeActionFeatures(play, f, 0, isPass: isPass);
    return f;
  }

  /// Write the action features of [play] into [out] starting at [offset].
  /// Lets hot paths reuse one buffer (state prefix + action suffix).
  void writeActionFeatures(
    final TichuTurn play,
    final List<double> out,
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
    final playedSlots = <int>{};
    for (final card in play.cards) {
      final slot = cardSlot(card);
      if (slot >= 0) playedSlots.add(slot);
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
        if (!playedSlots.contains(slot)) slot,
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

  static bool _isLead(final DeckState deck) =>
      deck.turn.type == TurnType.empty ||
      deck.turn.type == TurnType.none ||
      deck.turn.type == TurnType.dog;

  static int _seatOf(final GameSnapshot snapshot, final String playerId) {
    for (final p in snapshot.players) {
      if (p.id == playerId) return p.seat;
    }
    return 0;
  }

  static List<int> _slotsOf(final List<Card> cards) => [
    for (final c in cards)
      if (cardSlot(c) >= 0) cardSlot(c),
  ];

  /// Rank used for highest/lowest-rank features. A played phoenix takes its
  /// assigned value; dragon = 15, mahjong = 1, dog = 0.
  static double _effectiveRank(final Card card) => switch (card.face) {
    CardFace.dragon => 15,
    CardFace.dog || CardFace.none => 0,
    CardFace.phoenix => card.value.clamp(0.0, 15.0),
    _ => faceRank(card.face).toDouble(),
  };

  /// Index into the 17-wide rank histogram (r2..rA, mahjong, dog, phoenix,
  /// dragon) or -1.
  static int _histIndex(final Card card) => switch (card.face) {
    CardFace.mahJong => 13,
    CardFace.dog => 14,
    CardFace.phoenix => 15,
    CardFace.dragon => 16,
    CardFace.none => -1,
    _ => faceRank(card.face) - 2,
  };
}
