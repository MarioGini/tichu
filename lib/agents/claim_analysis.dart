import 'dart:typed_data';

import 'package:tichu/agents/card_knowledge.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// "Safe finish" analysis: can a hand be played out by a sequence of plays
/// that no unseen non-bomb combination beats?
///
/// A **claim partition** splits a hand into legal combinations. Holding the
/// lead, the player plays the unbeatable ones one by one (each wins its trick
/// unless someone bombs, and the player leads again) and goes out with the
/// last one, which may be beatable. So a hand is *claimable* when some
/// partition has at most one beatable combination.
///
/// [ClaimSolver.of] answers, for a hand H and the unseen cards of one
/// decision:
///  * `minBeatable`: the minimum over partitions of H of the number of
///    beatable combinations (exact, no cap; features cap it at 4);
///  * `unbeatable`: the largest number of unbeatable combinations among the
///    partitions with `minBeatable` beatable ones.
///
/// Rules:
///  * Combinations are the leads of the move generator
///    (`generateLegalTurns` on an empty table) for the cards still in the
///    partition, taken from the lowest rank up: singles, pairs, triplets,
///    full houses, straights (the Mah Jong counts as 1), pair straights,
///    four-of-a-kind and straight-flush bombs. The generator's Phoenix rules
///    are kept: it pairs with any rank, makes a triplet of a pair, completes
///    a full house only with a rank held once (pair) or twice (triplet),
///    fills one missing rank of a straight (at the top, inside, or below a
///    run that ends at the ace, never a rank the hand holds) and one card of
///    one pair of a pair straight; never in a bomb. Combinations are found
///    from rank counts, not by calling the generator;
///    `test/agents/claim_analysis_test.dart` compares the result with a
///    brute force over the generator's leads. (One generator quirk is not
///    copied: it pads a pair straight of twos with Mah Jong + Phoenix.)
///    Straight flushes: every run of five or more in one colour is a bomb
///    (the generator lists only the longest run per colour; the shorter
///    ones are bombs by the rules and can matter when the rest of the run
///    is needed elsewhere).
///  * Beatable = [CardKnowledge.canBeBeaten] (unseen cards, bombs ignored),
///    computed as one threshold per combination type and length; bombs and
///    the Dragon count as unbeatable.
///  * The Dog counts as **beatable**: nobody can beat it, but it hands the
///    lead to the partner, so it is only safe as the last play.
///
/// Algorithm: rank-level dynamic programme. Colours only matter for straight
/// flushes, so those are chosen first (every set of disjoint straight flushes
/// of the hand, usually none); the rest is a multiset of ranks 1..14 plus the
/// Phoenix, keyed by a mixed-radix integer. The solver always removes a
/// combination containing the lowest remaining rank (every partition has
/// exactly one), with memoisation. The score `64 * beatable - unbeatable` is
/// additive and minimising it gives the lexicographic optimum.
///
/// The memo depends on the unseen cards only through the 20 beatability
/// thresholds, so memo tables are kept per threshold signature across
/// decisions (bounded; results never depend on the cache). Keys use plain
/// arithmetic, never bit operations above 32 bits (dart2js).
class ClaimSolver {
  /// Highest value of an unseen combination per kind (see [_kSingle] etc.):
  /// a combination of value v is unbeatable iff v >= threshold. 0 = nothing
  /// unseen of that kind, 15 = everything of that kind can be beaten.
  final List<int> _threshold;

  /// Memo of the capped search (the features) and, on demand, of the
  /// exact one ([ofSlots]).
  final _ClaimMemo _memo;
  late final _ClaimMemo _exactMemo = _ClaimMemo.forThresholds(
    _threshold,
    capped: false,
  );

  // Threshold slots.
  static const int _kSingle = 0;
  static const int _kPair = 1;
  static const int _kTriplet = 2;
  static const int _kFullHouse = 3;
  static const int _kStraight = 4; // + (length - 5), lengths 5..14
  static const int _kPairStraight = 14; // + (pairs - 2), 2..7 pairs
  static const int _kinds = 20;

  ClaimSolver._(this._threshold)
    : _memo = _ClaimMemo.forThresholds(_threshold, capped: true);

  /// Solver for the unseen cards of [k]. Outside the play phase (nothing
  /// tracked) every non-bomb combination counts as beatable, as in
  /// [CardKnowledge.canBeBeaten].
  ///
  /// Solvers are cached by the unseen rank counts (every decision builds
  /// one; the thresholds are only recomputed when the unseen cards change).
  factory ClaimSolver.of(CardKnowledge k) {
    if (!k.isTracking) {
      return _untracked ??= ClaimSolver._(List<int>.filled(_kinds, 15));
    }
    final u = k.unseenRankCounts;
    // Mixed-radix key of the unseen counts (< 2^36; plain arithmetic).
    var key = (k.phoenixUnseen ? 1 : 0) + (k.dragonUnseen ? 2 : 0);
    var w = 4;
    for (var r = 1; r <= 14; r++) {
      key += u[r] * w;
      w *= 5;
    }
    final hit = _byUnseen[key];
    if (hit != null) return hit;
    if (_byUnseen.length >= 4096) _byUnseen.clear();
    return _byUnseen[key] = ClaimSolver.fromUnseen(
      unseenRank: u,
      phoenix: k.phoenixUnseen,
      dragon: k.dragonUnseen,
    );
  }

  static ClaimSolver? _untracked;
  static final Map<int, ClaimSolver> _byUnseen = <int, ClaimSolver>{};

  /// Solver from unseen counts per rank ([unseenRank] index 1 = Mah Jong,
  /// 2..14) and whether the Phoenix / Dragon are unseen.
  factory ClaimSolver.fromUnseen({
    required List<int> unseenRank,
    required bool phoenix,
    required bool dragon,
  }) => ClaimSolver._(_thresholds(unseenRank, phoenix, dragon));

  /// Claim analysis of the hand given as card slots (see [cardSlot]).
  /// Exact, for any number of beatable combinations.
  ClaimResult ofSlots(List<int> slots) =>
      ClaimResult.fromScore(scoreOfSlots(slots, capped: false));

  /// Rank counts of the hand being analysed (index 1 = Mah Jong, 2..14);
  /// scratch space, the solver is not re-entrant.
  static final List<int> _counts = List<int>.filled(15, 0);

  /// `64 * minBeatable - unbeatable` of the hand [slots] (see
  /// [ClaimResult.fromScore]); allocation-free unless the hand holds a
  /// straight flush. The hot path of the feature encoder.
  ///
  /// With [capped] (the features) the result is exact while the hand needs
  /// fewer than [ClaimResult.cap] beatable combinations and `64 * cap`
  /// otherwise: the search returns `64 * cap` for every position whose
  /// lower bound ([_unsafeSingletons]) reaches the cap, which prunes most
  /// of the search for full hands. Without it the search is exhaustive.
  int scoreOfSlots(List<int> slots, {bool capped = true}) =>
      _score(slots, capped: capped).score;

  /// The claim score of a hand plus what [after] needs to answer for its
  /// sub-hands from the memo.
  ClaimHand hand(List<int> slots) => _score(slots, capped: true);

  /// Score of [hand] minus the cards [played] ([remaining] = the slots left):
  /// a memo lookup by key arithmetic when the position is known, else
  /// [scoreOfSlots] of [remaining].
  int after(ClaimHand hand, List<Card> played, List<int> remaining) {
    if (!hand._flush) {
      var key = hand._key;
      var extra = hand._extra;
      for (final card in played) {
        final slot = cardSlot(card);
        if (slot < 0) {
          continue;
        } else if (slot < 52) {
          key -= _stride[2 + slot % 13];
        } else if (slot == CardKnowledge.mahJongSlot) {
          key -= _stride[1];
        } else if (slot == CardKnowledge.phoenixSlot) {
          key -= 1;
        } else if (slot == CardKnowledge.dragonSlot) {
          extra += 1;
        } else if (slot == CardKnowledge.dogSlot) {
          extra -= 64;
        }
      }
      final known = _memo.lookup(key);
      if (known != null) return known + extra;
    }
    return scoreOfSlots(remaining);
  }

  ClaimHand _score(List<int> slots, {required bool capped}) {
    final counts = _counts;
    for (var r = 1; r <= 14; r++) {
      counts[r] = 0;
    }
    var ph = 0;
    var extra = 0;
    var key = 0;
    // Per colour: bit mask of ranks (bit = rank, 2..14).
    var black = 0;
    var green = 0;
    var red = 0;
    var blue = 0;
    for (final slot in slots) {
      if (slot < 52) {
        final rank = 2 + slot % 13;
        counts[rank]++;
        key += _stride[rank];
        switch (slot ~/ 13) {
          case 0:
            black |= 1 << rank;
          case 1:
            green |= 1 << rank;
          case 2:
            red |= 1 << rank;
          default:
            blue |= 1 << rank;
        }
      } else if (slot == CardKnowledge.mahJongSlot) {
        counts[1]++;
        key += _stride[1];
      } else if (slot == CardKnowledge.phoenixSlot) {
        ph = 1;
        key += 1;
      } else if (slot == CardKnowledge.dragonSlot) {
        extra -= 1; // unbeatable single
      } else if (slot == CardKnowledge.dogSlot) {
        extra += 64; // only safe as the last play
      }
    }
    if (!_hasRun(black) && !_hasRun(green) && !_hasRun(red) && !_hasRun(blue)) {
      if (capped) {
        final lower = _unsafeSingletons(counts, ph, _threshold);
        if (lower >= ClaimResult.cap) {
          _memo.remember(key, _ClaimMemo._capScore);
          return ClaimHand._(64 * ClaimResult.cap, key, extra, false);
        }
        if (lower + (extra >= 63 ? 1 : 0) >= ClaimResult.cap) {
          return ClaimHand._(64 * ClaimResult.cap, key, extra, false);
        }
      }
      final memo = capped ? _memo : _exactMemo;
      return ClaimHand._(
        memo.score(key, counts, ph, _threshold) + extra,
        key,
        extra,
        false,
      );
    }
    final flushes = _straightFlushes([black, green, red, blue]);
    return ClaimHand._(
      _bestWithFlushes(
            capped ? _memo : _exactMemo,
            flushes,
            0,
            key,
            counts,
            ph,
          ) +
          extra,
      key,
      extra,
      true,
    );
  }

  static final List<int> _runDown = List<int>.filled(16, 0);
  static final List<int> _runUp = List<int>.filled(16, 0);

  /// Lower bound on the beatable combinations of a hand without straight
  /// flushes: ranks held once that no unbeatable combination can contain
  /// (the single is beatable, no Phoenix pair / full house with it is
  /// unbeatable, and no straight through it is possible even with the
  /// Phoenix, generously). Each needs a beatable combination of its own:
  /// two such cards never fit in one full house, pair straight or straight.
  static int _unsafeSingletons(List<int> c, int ph, List<int> t) {
    final down = _runDown;
    final up = _runUp;
    for (var r = 1; r <= 14; r++) {
      down[r] = c[r] > 0 ? down[r - 1] + 1 : 0;
    }
    for (var r = 14; r >= 1; r--) {
      up[r] = c[r] > 0 ? up[r + 1] + 1 : 0;
    }
    var fullHouse = false;
    if (ph == 1) {
      for (var r = 2; r <= 14; r++) {
        if (c[r] >= 3 && r >= t[ClaimSolver._kFullHouse]) fullHouse = true;
      }
    }
    final single = t[ClaimSolver._kSingle];
    final pair = t[ClaimSolver._kPair];
    var n = 0;
    for (var r = 1; r <= 14; r++) {
      if (c[r] != 1 || r >= single) continue;
      if (ph == 1 &&
          r >= 2 &&
          (r >= pair ||
              fullHouse ||
              c[r - 1] >= 2 ||
              (r < 14 && c[r + 1] >= 2))) {
        continue; // Phoenix pair, full house or pair straight
      }
      final len = down[r] + up[r] - 1;
      if (len >= 5) continue;
      if (ph == 1) {
        final below = r - down[r]; // missing rank under the run (>= 0)
        final above = r + up[r]; // missing rank over the run (<= 15)
        final l2 = below >= 1 ? down[below - 1] : 0;
        final r2 = above <= 14 ? up[above + 1] : 0;
        if (len + 1 + l2 + r2 >= 5) continue;
      }
      n++;
    }
    return n;
  }

  static bool _hasRun(int m) =>
      m & (m >> 1) & (m >> 2) & (m >> 3) & (m >> 4) != 0;

  /// Every straight flush (rank run of >= 5 in one colour) as
  /// (colour, low, high).
  static List<(int, int, int)> _straightFlushes(List<int> colours) {
    List<(int, int, int)>? out;
    for (var c = 0; c < 4; c++) {
      final m = colours[c];
      if (!_hasRun(m)) continue;
      for (var lo = 2; lo <= 10; lo++) {
        for (var hi = lo; hi <= 14 && m & (1 << hi) != 0; hi++) {
          if (m & (1 << lo) == 0) break;
          if (hi - lo >= 4) (out ??= []).add((c, lo, hi));
        }
      }
    }
    return out ?? const [];
  }

  /// Best score when choosing any set of disjoint straight flushes from
  /// [flushes] (index >= [from]) as bombs, the rest by the rank solver.
  int _bestWithFlushes(
    _ClaimMemo memo,
    List<(int, int, int)> flushes,
    int from,
    int key,
    List<int> counts,
    int ph, [
    List<(int, int, int)> used = const [],
  ]) {
    var best = memo.score(key, counts, ph, _threshold);
    for (var i = from; i < flushes.length; i++) {
      final (c, lo, hi) = flushes[i];
      var overlaps = false;
      for (final (uc, ulo, uhi) in used) {
        if (uc == c && lo <= uhi && ulo <= hi) overlaps = true;
      }
      if (overlaps) continue;
      var k = key;
      for (var r = lo; r <= hi; r++) {
        counts[r]--;
        k -= _stride[r];
      }
      final s =
          _bestWithFlushes(memo, flushes, i + 1, k, counts, ph, [
            ...used,
            flushes[i],
          ]) -
          1;
      for (var r = lo; r <= hi; r++) {
        counts[r]++;
      }
      if (s < best) best = s;
    }
    return best;
  }

  /// Unbeatability thresholds, mirroring [CardKnowledge.canBeBeaten]: the
  /// highest value of each kind the unseen cards can form, searched from
  /// the top with prefix sums (O(1) per straight window).
  static List<int> _thresholds(List<int> u, bool phx, bool dragon) {
    final t = List<int>.filled(_kinds, 0);
    // Singles: the Dragon or the Phoenix beat every other single.
    if (dragon || phx) {
      t[_kSingle] = 15;
    } else {
      for (var r = 14; r >= 1; r--) {
        if (u[r] >= 1) {
          t[_kSingle] = r;
          break;
        }
      }
    }
    for (var r = 14; r >= 2; r--) {
      if (u[r] >= 2 || (phx && u[r] >= 1)) {
        t[_kPair] = r;
        break;
      }
    }
    for (var r = 14; r >= 2; r--) {
      if (u[r] >= 3 || (phx && u[r] >= 2)) {
        t[_kTriplet] = r;
        break;
      }
    }
    // Ranks with a natural pair, and with exactly one card.
    var pairs = 0;
    var ones = 0;
    for (var r = 2; r <= 14; r++) {
      if (u[r] >= 2) pairs++;
      if (u[r] == 1) ones++;
    }
    for (var top = 14; top >= 2; top--) {
      final natural = u[top] >= 3;
      if (!natural && !(phx && u[top] == 2)) continue;
      // Another rank with a pair, or (natural triplet) a single + Phoenix.
      final otherPairs = pairs - (u[top] >= 2 ? 1 : 0);
      if (otherPairs > 0 || (natural && phx && ones > 0)) {
        t[_kFullHouse] = top;
        break;
      }
    }
    // Prefix sums over ranks 1..14: ranks with no unseen card, and the
    // cards missing for a pair.
    final absent = _absent;
    final deficit = _deficit;
    for (var r = 1; r <= 14; r++) {
      final n = u[r];
      absent[r] = absent[r - 1] + (n < 1 ? 1 : 0);
      deficit[r] = deficit[r - 1] + (n >= 2 ? 0 : 2 - n);
    }
    final mahJongMissing = u[1] < 1;
    for (var len = 5; len <= 14; len++) {
      for (var top = 14; top >= len; top--) {
        final low = top - len + 1;
        final missing = absent[top] - absent[low - 1];
        if (missing == 0 ||
            (missing == 1 && phx && !(low == 1 && mahJongMissing))) {
          t[_kStraight + len - 5] = top;
          break;
        }
      }
    }
    for (var n = 2; n <= 7; n++) {
      for (var top = 14; top >= n + 1; top--) {
        final missing = deficit[top] - deficit[top - n];
        if (missing == 0 || (missing == 1 && phx)) {
          t[_kPairStraight + n - 2] = top;
          break;
        }
      }
    }
    return t;
  }

  static final List<int> _absent = List<int>.filled(15, 0);
  static final List<int> _deficit = List<int>.filled(15, 0);
}

/// A hand analysed by [ClaimSolver.hand]: its score and the state key that
/// [ClaimSolver.after] derives its sub-hands from.
class ClaimHand {
  /// `64 * minBeatable - unbeatable` (capped, see [ClaimSolver.scoreOfSlots]).
  final int score;
  final int _key;
  final int _extra;
  final bool _flush;

  const ClaimHand._(this.score, this._key, this._extra, this._flush);
}

/// Result of [ClaimSolver.ofSlots].
class ClaimResult {
  /// Minimum number of beatable combinations over all partitions.
  final int minBeatable;

  /// Unbeatable combinations in a best partition (most among those with
  /// [minBeatable] beatable ones).
  final int unbeatable;

  const ClaimResult(this.minBeatable, this.unbeatable);

  /// From a solver score `64 * minBeatable - unbeatable`.
  factory ClaimResult.fromScore(int score) {
    final b = (score + 63) ~/ 64;
    return ClaimResult(b, 64 * b - score);
  }

  /// Cap of the features: [minBeatable] is reported up to this value, and
  /// [unbeatable] only below it.
  static const int cap = 4;

  /// Playable as unbeatable leads plus one last play.
  bool get claimable => minBeatable <= 1;

  /// Write the 3 normalised claim features at [offset]: min beatable (capped
  /// at [cap]) / 4, unbeatable (capped at 7; 0 when min beatable reaches the
  /// cap) / 7, claimable flag.
  void writeTo(List<double> out, int offset) =>
      writeScore(64 * minBeatable - unbeatable, out, offset);

  /// [writeTo] for a solver score, without allocating a result.
  static void writeScore(int score, List<double> out, int offset) {
    final b = (score + 63) ~/ 64;
    final u = b < cap ? 64 * b - score : 0;
    out[offset] = (b < cap ? b : cap) / 4.0;
    out[offset + 1] = (u < 7 ? u : 7) / 7.0;
    out[offset + 2] = b <= 1 ? 1.0 : 0.0;
  }

  @override
  String toString() => 'ClaimResult($minBeatable, $unbeatable)';
}

/// Mixed-radix key weights: phoenix = 1, rank r (1..14) = 2 * 5^(r-1).
final List<int> _stride = () {
  final s = List<int>.filled(15, 0);
  var w = 2;
  for (var r = 1; r <= 14; r++) {
    s[r] = w;
    w *= 5;
  }
  return s;
}();

/// Memo of the rank solver for one threshold signature: a signature id in
/// one global open-addressing table (state key + id -> score), shared by all
/// decisions with the same thresholds. Keys and hashes use plain arithmetic
/// below 2^53 (dart2js-safe).
class _ClaimMemo {
  final int s0;
  final int s1;
  final int s2;

  /// Id of the signature in the current table generation (see [_ensure]).
  int _id = 0;
  int _generation = -1;

  /// Capped search: positions that need [ClaimResult.cap] or more
  /// beatable combinations all score `64 * cap`.
  final bool capped;

  _ClaimMemo(this.s0, this.s1, this.s2, {required this.capped});

  static const int _capScore = 64 * ClaimResult.cap;

  static final Map<int, _ClaimMemo> _bySignature = <int, _ClaimMemo>{};

  // The table: 2^19 slots (~5 MB), cleared between top-level queries once
  // half full, or when the signature ids run out.
  static const int _bits = 19;
  static const int _size = 1 << _bits;
  static const int _mask = _size - 1;
  static const int _maxIds = 1 << 12;

  /// State-key stride per signature id (state keys are < 2 * 5^14 < 2^34).
  static const int _idStride = 17179869184; // 2^34

  static Float64List? _keys;
  static Int16List? _values;
  static int _count = 0;
  static int _nextId = 1;
  static int _currentGeneration = 0;

  factory _ClaimMemo.forThresholds(List<int> t, {required bool capped}) {
    // 20 thresholds of 4 bits in three 28-bit words (dart2js-safe).
    var s0 = 0;
    var s1 = 0;
    var s2 = 0;
    for (var i = 0; i < 7; i++) {
      s0 |= t[i] << (4 * i);
      s1 |= t[7 + i] << (4 * i);
      if (14 + i < t.length) s2 |= t[14 + i] << (4 * i);
    }
    if (capped) s2 |= 1 << 27;
    final h = Object.hash(s0, s1, s2);
    final hit = _bySignature[h];
    if (hit != null && hit.s0 == s0 && hit.s1 == s1 && hit.s2 == s2) {
      return hit;
    }
    if (_bySignature.length >= _maxIds) _bySignature.clear();
    return _bySignature[h] = _ClaimMemo(s0, s1, s2, capped: capped);
  }

  /// Make sure this signature has an id in the current table; clears the
  /// table when it is half full. Only called before a top-level query, so
  /// a clear never happens in the middle of a search.
  void _ensure() {
    if (_count >= _size >> 1 || _nextId >= _maxIds) {
      _keys!.fillRange(0, _size, 0);
      _count = 0;
      _nextId = 1;
      _currentGeneration++;
    }
    if (_generation != _currentGeneration) {
      _keys ??= Float64List(_size);
      _values ??= Int16List(_size);
      _id = _nextId++;
      _generation = _currentGeneration;
    }
  }

  /// Score of the hand (state [key], rank counts [c], [ph] Phoenix) under
  /// thresholds [t]; see [solve].
  int score(int key, List<int> c, int ph, List<int> t) {
    if (_keys == null ||
        _generation != _currentGeneration ||
        _count >= _size >> 1) {
      _ensure();
    }
    return solve(key, c, ph, t);
  }

  /// The memoised score of state [key], or null.
  int? lookup(int key) {
    if (key == 0) return 0;
    if (_keys == null ||
        _generation != _currentGeneration ||
        _count >= _size >> 1) {
      _ensure();
    }
    final keys = _keys!;
    final full = (_id * _idStride + key).toDouble();
    var slot = _slotOf(key);
    while (true) {
      final k = keys[slot];
      if (k == full) return _values![slot];
      if (k == 0) return null;
      slot = (slot + 1) & _mask;
    }
  }

  /// Store a score found without the search (the lower bound).
  void remember(int key, int score) {
    if (key == 0) return;
    if (_keys == null ||
        _generation != _currentGeneration ||
        _count >= _size >> 1) {
      _ensure();
    }
    _store((_id * _idStride + key).toDouble(), key, score);
  }

  int _slotOf(int key) =>
      ((key % 1000003) * 1031 + (key ~/ 1000003) * 7 + _id * 92821) & _mask;

  /// Minimum of `64 * beatable - unbeatable` over the partitions of the
  /// rank multiset [c] (index 1..14) plus [ph] Phoenix, with key [key].
  /// [c] is modified during the search and restored.
  int solve(int key, List<int> c, int ph, List<int> t) {
    if (key == 0) return 0;
    final keys = _keys!;
    final full = (_id * _idStride + key).toDouble();
    var slot = _slotOf(key);
    while (true) {
      final k = keys[slot];
      if (k == full) return _values![slot];
      if (k == 0) break;
      slot = (slot + 1) & _mask;
    }

    var a = 1;
    while (a <= 14 && c[a] == 0) {
      a++;
    }
    int best;
    if (a > 14) {
      // Only the Phoenix is left: a single of value 1.5.
      best = t[ClaimSolver._kSingle] <= 1 ? -1 : 64;
      _store(full, key, best);
      return best;
    }

    if (capped && ClaimSolver._unsafeSingletons(c, ph, t) >= ClaimResult.cap) {
      _store(full, key, _capScore);
      return _capScore;
    }

    final ca = c[a];
    final sa = _stride[a];
    // Single.
    c[a]--;
    best = _cost(t, ClaimSolver._kSingle, a) + solve(key - sa, c, ph, t);
    c[a]++;

    if (a >= 2) {
      // Pairs, triplets, four of a kind (natural or with the Phoenix).
      for (var n = 2; n <= 4; n++) {
        for (var p = 0; p <= ph; p++) {
          final nat = n - p;
          if (nat > ca || (n == 4 && p == 1)) continue;
          final kind = n == 2
              ? ClaimSolver._kPair
              : n == 3
              ? ClaimSolver._kTriplet
              : -1;
          c[a] -= nat;
          final s =
              (kind < 0 ? -1 : _cost(t, kind, a)) +
              solve(key - nat * sa - p, c, ph - p, t);
          c[a] += nat;
          if (s < best) best = s;
        }
      }

      // Full houses: triplet of a + pair above, or pair of a + triplet
      // above; the Phoenix completes at most one of the two.
      for (var o = a + 1; o <= 14; o++) {
        final co = c[o];
        if (co == 0) continue;
        final so = _stride[o];
        for (var aTriplet = 0; aTriplet <= 1; aTriplet++) {
          final needA = aTriplet == 1 ? 3 : 2;
          final needO = aTriplet == 1 ? 2 : 3;
          final value = aTriplet == 1 ? a : o;
          // p = 0: natural; 1: Phoenix in a's part; 2: Phoenix in o's part.
          // As in the generator, the Phoenix only completes a rank held
          // exactly once (pair) or twice (triplet).
          for (var p = 0; p <= 2 * ph; p++) {
            final natA = needA - (p == 1 ? 1 : 0);
            final natO = needO - (p == 2 ? 1 : 0);
            if (natA > ca || natO > co) continue;
            if ((p == 1 && ca != natA) || (p == 2 && co != natO)) continue;
            c[a] -= natA;
            c[o] -= natO;
            final s =
                _cost(t, ClaimSolver._kFullHouse, value) +
                solve(
                  key - natA * sa - natO * so - (p > 0 ? 1 : 0),
                  c,
                  p > 0 ? 0 : ph,
                  t,
                );
            c[a] += natA;
            c[o] += natO;
            if (s < best) best = s;
          }
        }
      }

      // Pair straights from a upwards; the Phoenix may replace one card.
      // Ranks a..hi are removed cumulatively and restored afterwards.
      var k = key;
      var phRank = 0;
      var hi = a;
      for (; hi <= 14; hi++) {
        final ch = c[hi];
        if (ch >= 2) {
          c[hi] -= 2;
          k -= 2 * _stride[hi];
        } else if (ch == 1 && phRank == 0 && ph == 1) {
          phRank = hi;
          c[hi] -= 1;
          k -= _stride[hi] + 1;
        } else {
          break;
        }
        if (hi > a) {
          final s =
              _cost(t, ClaimSolver._kPairStraight + hi - a - 1, hi) +
              solve(k, c, phRank == 0 ? ph : 0, t);
          if (s < best) best = s;
        }
      }
      for (var r = a; r < hi; r++) {
        c[r] += r == phRank ? 1 : 2;
      }
    }

    // Straights from a upwards; the Phoenix fills at most one missing rank:
    // inside, at the top, or (as in the generator) just below a run that
    // ends at the ace; never the Mah Jong's.
    for (var phBelow = 0; phBelow <= ph; phBelow++) {
      if (phBelow == 1 && (a < 3 || !_runToAce(c, a))) break;
      final lo = a - phBelow;
      var k = key - phBelow;
      var gap = phBelow == 1 ? lo : 0;
      var hi = a;
      for (; hi <= 14; hi++) {
        if (c[hi] >= 1) {
          c[hi]--;
          k -= _stride[hi];
        } else if (gap == 0 && ph == 1) {
          gap = hi;
          k -= 1;
        } else {
          break;
        }
        if (hi - lo >= 4) {
          final s =
              _cost(t, ClaimSolver._kStraight + hi - lo - 4, hi) +
              solve(k, c, gap == 0 ? ph : 0, t);
          if (s < best) best = s;
        }
      }
      for (var r = a; r < hi; r++) {
        if (r != gap) c[r]++;
      }
    }

    if (capped && best > _capScore - 64) best = _capScore;
    _store(full, key, best);
    return best;
  }

  static bool _runToAce(List<int> c, int a) {
    for (var r = a; r <= 14; r++) {
      if (c[r] == 0) return false;
    }
    return true;
  }

  /// Insert (the search may have filled slots since the lookup).
  void _store(double full, int key, int score) {
    final keys = _keys!;
    var slot = _slotOf(key);
    while (keys[slot] != 0) {
      if (keys[slot] == full) return;
      slot = (slot + 1) & _mask;
    }
    keys[slot] = full;
    _values![slot] = score;
    _count++;
  }

  static int _cost(List<int> t, int kind, int value) =>
      value >= t[kind] ? -1 : 64;
}
