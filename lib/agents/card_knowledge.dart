import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// Exact, public card knowledge for one player at one point of a round.
///
/// Every card is either in my hand, already played (visible to everyone),
/// or *unseen* (somewhere in the other three hands). In the play phase the
/// played set equals the complement of all hands in the snapshot, so this is
/// deterministic and leaks nothing about who holds which unseen card.
/// Requires a full-information [GameSnapshot] (local engine / headless); in
/// other phases nothing is tracked and every query answers conservatively.
///
/// Shared by the heuristic agent and the NN feature encoder. Use
/// [CardKnowledge.of] to get a per-snapshot cached instance.
class CardKnowledge {
  final String playerId;

  /// False outside the play phase: then [isSlotPlayed] is always false and
  /// [canBeBeaten] always true.
  final bool isTracking;

  /// Per slot (see [cardSlot]): 1 = my hand, 2 = unseen, 0 = played.
  final List<int> _owner;

  /// Unseen copies per rank, index = [faceRank] (1 = mahjong, 2..14).
  final List<int> _unseenRank;

  static const int slotCount = 56;
  static const int mahJongSlot = 52;
  static const int dogSlot = 53;
  static const int phoenixSlot = 54;
  static const int dragonSlot = 55;

  static final Expando<Map<String, CardKnowledge>> _cache = Expando();

  /// Cached instance for ([snapshot], [playerId]). Snapshots are immutable
  /// views, so the analysis is done at most once per snapshot and player.
  factory CardKnowledge.of(final GameSnapshot snapshot, final String playerId) {
    final byPlayer = _cache[snapshot] ??= <String, CardKnowledge>{};
    return byPlayer[playerId] ??= CardKnowledge.fromSnapshot(
      snapshot,
      playerId,
    );
  }

  CardKnowledge.fromSnapshot(final GameSnapshot snapshot, this.playerId)
    : isTracking = snapshot.phase == GamePhase.play,
      _owner = List<int>.filled(slotCount, 0),
      _unseenRank = List<int>.filled(15, 0) {
    for (final card in snapshot.hands[playerId] ?? const <Card>[]) {
      final slot = cardSlot(card);
      if (slot >= 0) _owner[slot] = 1;
    }
    if (!isTracking) return;
    for (final entry in snapshot.hands.entries) {
      if (entry.key == playerId) continue;
      for (final card in entry.value) {
        final slot = cardSlot(card);
        if (slot >= 0 && _owner[slot] == 0) _owner[slot] = 2;
      }
    }
    for (var slot = 0; slot < 52; slot++) {
      if (_owner[slot] == 2) _unseenRank[2 + slot % 13]++;
    }
    if (_owner[mahJongSlot] == 2) _unseenRank[1] = 1;
  }

  // ── Basic queries ────────────────────────────────────────────────────────

  /// Held by one of the other three players (false when not tracking).
  bool isUnseen(final Card card) => isTracking && _slotIs(card, 2);

  bool isSlotPlayed(final int slot) => isTracking && _owner[slot] == 0;

  /// Unseen copies of [face] (0..4; 0..1 for specials).
  int unseenCount(final CardFace face) {
    if (!isTracking) return 0;
    return switch (face) {
      CardFace.dog => _owner[dogSlot] == 2 ? 1 : 0,
      CardFace.phoenix => _owner[phoenixSlot] == 2 ? 1 : 0,
      CardFace.dragon => _owner[dragonSlot] == 2 ? 1 : 0,
      CardFace.none => 0,
      _ => _unseenRank[faceRank(face)],
    };
  }

  /// Unseen copies per rank, index = [faceRank] (1 = Mah Jong, 2..14);
  /// all zero when not tracking. A view of the internal counts: do not
  /// modify.
  List<int> get unseenRankCounts => _unseenRank;

  bool get phoenixUnseen => unseenCount(CardFace.phoenix) == 1;
  bool get dragonUnseen => unseenCount(CardFace.dragon) == 1;
  bool get dogUnseen => unseenCount(CardFace.dog) == 1;

  // ── Beatability ──────────────────────────────────────────────────────────

  /// Whether the unseen cards can form a non-bomb play that beats [play].
  ///
  /// Bombs are deliberately ignored: the bomb threat always exists and is
  /// rare. Examples: a single ace cannot be beaten once dragon and phoenix
  /// are out; a pair of kings once no two aces (or ace + phoenix) remain.
  /// Conservative (`true`) when not tracking.
  bool canBeBeaten(final TichuTurn play) {
    if (!isTracking) return true;
    if (play.cards.isEmpty) return true;
    final u = _unseenRank;
    final phx = phoenixUnseen;
    final v = play.value;
    final n = play.cards.length;
    switch (play.type) {
      case TurnType.single:
        final face = play.cards.first.face;
        if (face == CardFace.dragon || face == CardFace.dog) return false;
        if (dragonUnseen || phx) return true;
        for (var r = 2; r <= 14; r++) {
          if (r > v && u[r] >= 1) return true;
        }
        return false;
      case TurnType.pair || TurnType.triplet:
        final k = play.type == TurnType.pair ? 2 : 3;
        for (var r = 2; r <= 14; r++) {
          if (r > v && (u[r] >= k || (phx && u[r] == k - 1))) return true;
        }
        return false;
      case TurnType.fullHouse:
        // Higher triplet plus any pair of another rank; the phoenix can
        // complete at most one of the two.
        for (var t = 2; t <= 14; t++) {
          if (t <= v) continue;
          final tripletNeedsPhoenix = u[t] < 3;
          if (tripletNeedsPhoenix && !(phx && u[t] == 2)) continue;
          for (var p = 2; p <= 14; p++) {
            if (p == t) continue;
            if (u[p] >= 2 || (!tripletNeedsPhoenix && phx && u[p] == 1)) {
              return true;
            }
          }
        }
        return false;
      case TurnType.straight:
        for (var top = v.floor() + 1; top <= 14; top++) {
          final low = top - n + 1;
          if (low < 1) continue;
          var missing = 0;
          var missingIsMahJong = false;
          for (var r = low; r <= top; r++) {
            if (u[r] < 1) {
              missing++;
              if (r == 1) missingIsMahJong = true;
            }
          }
          if (missing == 0 || (missing == 1 && phx && !missingIsMahJong)) {
            return true;
          }
        }
        return false;
      case TurnType.pairStraight:
        final pairs = n ~/ 2;
        for (var top = v.floor() + 1; top <= 14; top++) {
          final low = top - pairs + 1;
          if (low < 2) continue;
          var missing = 0;
          for (var r = low; r <= top; r++) {
            missing += u[r] >= 2 ? 0 : 2 - u[r];
          }
          if (missing == 0 || (missing == 1 && phx)) return true;
        }
        return false;
      case TurnType.bomb || TurnType.dog:
        return false;
      case TurnType.none || TurnType.empty:
        return true;
    }
  }

  /// How many distinct non-bomb plays of the unseen cards beat [play]: for
  /// a single the unseen higher cards (Phoenix and Dragon included), for
  /// other types the higher ranks (pairs, triplets, full houses by triplet
  /// rank) or tops (straights, pair straights) the unseen cards can form.
  /// A graded [canBeBeaten] (0 = unbeatable).
  int beaterCount(final TichuTurn play) {
    if (!isTracking || play.cards.isEmpty) return 0;
    final u = _unseenRank;
    final phx = phoenixUnseen;
    final v = play.value;
    final n = play.cards.length;
    var count = 0;
    switch (play.type) {
      case TurnType.single:
        final face = play.cards.first.face;
        if (face == CardFace.dragon || face == CardFace.dog) return 0;
        for (var r = 2; r <= 14; r++) {
          if (r > v) count += u[r];
        }
        if (phx) count++;
        if (dragonUnseen) count++;
      case TurnType.pair || TurnType.triplet:
        final k = play.type == TurnType.pair ? 2 : 3;
        for (var r = 2; r <= 14; r++) {
          if (r > v && (u[r] >= k || (phx && u[r] == k - 1))) count++;
        }
      case TurnType.fullHouse:
        for (var t = 2; t <= 14; t++) {
          if (t > v && (u[t] >= 3 || (phx && u[t] == 2))) count++;
        }
      case TurnType.straight:
        for (var top = v.floor() + 1; top <= 14; top++) {
          final low = top - n + 1;
          if (low < 1) continue;
          var missing = 0;
          var missingIsMahJong = false;
          for (var r = low; r <= top; r++) {
            if (u[r] < 1) {
              missing++;
              if (r == 1) missingIsMahJong = true;
            }
          }
          if (missing == 0 || (missing == 1 && phx && !missingIsMahJong)) {
            count++;
          }
        }
      case TurnType.pairStraight:
        final pairs = n ~/ 2;
        for (var top = v.floor() + 1; top <= 14; top++) {
          final low = top - pairs + 1;
          if (low < 2) continue;
          var missing = 0;
          for (var r = low; r <= top; r++) {
            missing += u[r] >= 2 ? 0 : 2 - u[r];
          }
          if (missing == 0 || (missing == 1 && phx)) count++;
        }
      case TurnType.bomb || TurnType.dog || TurnType.none || TurnType.empty:
        return 0;
    }
    return count;
  }

  /// Unseen cards in total (the other players' hands).
  int get unseenTotal {
    var n = 0;
    for (var r = 1; r <= 14; r++) {
      n += _unseenRank[r];
    }
    if (phoenixUnseen) n++;
    if (dragonUnseen) n++;
    if (dogUnseen) n++;
    return n;
  }

  /// `!canBeBeaten(play)`: wins the trick unless someone bombs.
  bool isUnbeatable(final TichuTurn play) => !canBeBeaten(play);

  /// Highest-value bomb the unseen cards can form, 0 if none (four of a
  /// kind = rank, straight flush = 20 + top, as in `validTurn`). The
  /// phoenix cannot be part of a bomb.
  late final double maxUnseenBombValue = _computeMaxUnseenBomb();

  bool get unseenBombPossible => maxUnseenBombValue > 0;

  double _computeMaxUnseenBomb() {
    if (!isTracking) return 0;
    var best = 0.0;
    for (var r = 2; r <= 14; r++) {
      if (_unseenRank[r] == 4) best = r.toDouble();
    }
    for (var color = 0; color < 4; color++) {
      var run = 0;
      for (var r = 2; r <= 14; r++) {
        run = _owner[color * 13 + r - 2] == 2 ? run + 1 : 0;
        if (run >= 5 && 20.0 + r > best) best = 20.0 + r;
      }
    }
    return best;
  }

  bool _slotIs(final Card card, final int owner) {
    final slot = cardSlot(card);
    return slot >= 0 && _owner[slot] == owner;
  }
}

/// Card slot in a 56-wide bitmap: `color*13 + (rank-2)` for normal cards
/// (black, green, red, blue; ranks 2..A), then 52 mahjong, 53 dog,
/// 54 phoenix, 55 dragon. -1 for an invalid card.
int cardSlot(final Card card) {
  switch (card.face) {
    case CardFace.mahJong:
      return CardKnowledge.mahJongSlot;
    case CardFace.dog:
      return CardKnowledge.dogSlot;
    case CardFace.phoenix:
      return CardKnowledge.phoenixSlot;
    case CardFace.dragon:
      return CardKnowledge.dragonSlot;
    case CardFace.none:
      return -1;
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
        CardFace.ace:
      if (card.color == CardColor.special) return -1;
      return card.color.index * 13 + faceRank(card.face) - 2;
  }
}

/// Natural rank: 2..14 for normal cards, 1 for mahjong, 0 otherwise.
int faceRank(final CardFace face) => switch (face) {
  CardFace.mahJong => 1,
  CardFace.two => 2,
  CardFace.three => 3,
  CardFace.four => 4,
  CardFace.five => 5,
  CardFace.six => 6,
  CardFace.seven => 7,
  CardFace.eight => 8,
  CardFace.nine => 9,
  CardFace.ten => 10,
  CardFace.jack => 11,
  CardFace.queen => 12,
  CardFace.king => 13,
  CardFace.ace => 14,
  CardFace.dragon || CardFace.phoenix || CardFace.dog || CardFace.none => 0,
};
