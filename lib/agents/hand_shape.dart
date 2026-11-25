import 'package:tichu/agents/card_knowledge.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// Cheap combinatorial summary of a hand, computed from rank histograms
/// (no move generation). Used for the `hand_structure` group and for the
/// hand remaining after an action.
class HandShape {
  final int singles;
  final int pairs;
  final int triplets;
  final int bombs;
  final int longestRun;
  final int longestPairRun;
  final bool hasStraight;
  final int estPlays;
  final int controls;
  final int lowSingles;

  const HandShape({
    required this.singles,
    required this.pairs,
    required this.triplets,
    required this.bombs,
    required this.longestRun,
    required this.longestPairRun,
    required this.hasStraight,
    required this.estPlays,
    required this.controls,
    required this.lowSingles,
  });

  /// Shape of [cards] (e.g. a hand, or what remains after a play).
  factory HandShape.fromCards(Iterable<Card> cards) => HandShape.fromSlots([
    for (final c in cards)
      if (cardSlot(c) >= 0) cardSlot(c),
  ]);

  /// Shape from card slots (see [cardSlot]).
  factory HandShape.fromSlots(List<int> slots) {
    final counts = List<int>.filled(15, 0); // index = rank (1 = mahjong)
    // Per colour: bit mask of the ranks held.
    var black = 0;
    var green = 0;
    var red = 0;
    var blue = 0;
    var phoenix = false;
    var dragon = false;
    var dog = false;
    for (final slot in slots) {
      if (slot < 52) {
        final rank = 2 + slot % 13;
        counts[rank]++;
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
      } else if (slot == CardKnowledge.dogSlot) {
        dog = true;
      } else if (slot == CardKnowledge.phoenixSlot) {
        phoenix = true;
      } else if (slot == CardKnowledge.dragonSlot) {
        dragon = true;
      }
    }

    var singles = 0;
    var pairs = 0;
    var triplets = 0;
    var quads = 0;
    var lowSingles = 0;
    var groups = 0;
    for (var r = 2; r <= 14; r++) {
      switch (counts[r]) {
        case 0:
          continue;
        case 1:
          singles++;
          if (r <= 10) lowSingles++;
        case 2:
          pairs++;
        case 3:
          triplets++;
        default:
          quads++;
      }
      groups++;
    }
    if (counts[1] > 0) {
      singles++;
      lowSingles++;
      groups++;
    }
    if (dragon) {
      singles++;
      groups++;
    }
    if (dog) {
      singles++;
      groups++;
    }

    // Straight-flush bombs: any colour with >= 5 consecutive ranks.
    var straightFlushes = 0;
    for (final m in [black, green, red, blue]) {
      if (m & (m >> 1) & (m >> 2) & (m >> 3) & (m >> 4) != 0) {
        straightFlushes++;
      }
    }

    // Longest straight (mahjong = rank 1), phoenix may fill one gap.
    var longestRun = 0;
    var bestRunSingles = 0;
    for (var start = 1; start <= 14; start++) {
      var gapUsed = !phoenix;
      var len = 0;
      var singlesInRun = 0;
      for (var r = start; r <= 14; r++) {
        if (counts[r] > 0) {
          len++;
          if (counts[r] == 1) singlesInRun++;
        } else if (!gapUsed) {
          gapUsed = true;
          len++;
        } else {
          break;
        }
      }
      if (len > longestRun) {
        longestRun = len;
        bestRunSingles = singlesInRun;
      }
    }

    var longestPairRun = 0;
    var pairRun = 0;
    for (var r = 2; r <= 14; r++) {
      pairRun = counts[r] >= 2 ? pairRun + 1 : 0;
      if (pairRun > longestPairRun) longestPairRun = pairRun;
    }

    final hasStraight = longestRun >= 5;
    var est = groups;
    if (hasStraight) est -= (bestRunSingles - 1).clamp(0, 14);
    est -= triplets < pairs ? triplets : pairs; // full houses
    if (est < 1 && slots.isNotEmpty) est = 1;
    if (slots.isEmpty) est = 0;

    final bombs = quads + straightFlushes;
    return HandShape(
      singles: singles,
      pairs: pairs,
      triplets: triplets,
      bombs: bombs,
      longestRun: longestRun,
      longestPairRun: longestPairRun,
      hasStraight: hasStraight,
      estPlays: est,
      controls: counts[14] + (dragon ? 1 : 0) + bombs,
      lowSingles: lowSingles,
    );
  }

  /// Write the 10 normalised shape features at [offset].
  void writeTo(List<double> out, int offset) {
    out[offset + 0] = singles / 14.0;
    out[offset + 1] = pairs / 7.0;
    out[offset + 2] = triplets / 4.0;
    out[offset + 3] = (bombs / 2.0).clamp(0.0, 1.0);
    out[offset + 4] = longestRun / 14.0;
    out[offset + 5] = longestPairRun / 7.0;
    out[offset + 6] = hasStraight ? 1.0 : 0.0;
    out[offset + 7] = estPlays / 14.0;
    out[offset + 8] = (controls / 6.0).clamp(0.0, 1.0);
    out[offset + 9] = lowSingles / 14.0;
  }
}
