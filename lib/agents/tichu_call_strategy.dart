import 'package:tichu/agents/hand_shape.dart';
import 'package:tichu/agents/heuristic_options.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/bomb_utils.dart';
import 'package:tichu/game/turn/utils/card_utils.dart';
import 'package:tichu/game/turn/utils/straight_utils.dart';

abstract class TichuCallStrategy {
  Future<bool> shouldCallGrandTichu(
    final GameSnapshot snapshot,
    final String playerId,
  );
  Future<bool> shouldCallTichu(
    final GameSnapshot snapshot,
    final String playerId,
  );

  /// Tichu call before passing cards (14 cards seen, nothing exchanged yet).
  /// Calling early tells the partner to support, e.g. with a strong pass.
  Future<bool> shouldCallTichuBeforeSchupf(
    final GameSnapshot snapshot,
    final String playerId,
  );
}

class DefaultTichuCallStrategy implements TichuCallStrategy {
  static const int _tichuIndexThreshold = 7;

  /// Announce Tichu before the exchange with a Tichu hand, so the partner
  /// passes over their best card (a partner who called gets it).
  @override
  Future<bool> shouldCallTichuBeforeSchupf(
    final GameSnapshot snapshot,
    final String playerId,
  ) async =>
      options.announceBeforeSchupf && await shouldCallTichu(snapshot, playerId);

  const DefaultTichuCallStrategy({this.options = HeuristicOptions.latest});

  final HeuristicOptions options;

  @override
  Future<bool> shouldCallGrandTichu(
    final GameSnapshot snapshot,
    final String playerId,
  ) async => false;

  @override
  Future<bool> shouldCallTichu(
    final GameSnapshot snapshot,
    final String playerId,
  ) async {
    final hand = snapshot.hands[playerId] ?? const <Card>[];
    // Calling against an opponent who already called rarely pays.
    final opponentCalled = snapshot.players.any(
      (final p) =>
          p.id != playerId &&
          p.seat % 2 !=
              snapshot.players.firstWhere((final q) => q.id == playerId).seat %
                  2 &&
          (snapshot.scoreState.tichuCalls[p.id] ?? TichuCall.none) !=
              TichuCall.none,
    );
    if (options.strictTichu) {
      // Hand-strength rule: harder (higher threshold) once an opponent has
      // called, but not forbidden.
      return tichuStrength(hand) >=
          (opponentCalled ? strengthThresholdVsCall : strengthThreshold);
    }
    return !opponentCalled && _legacyTichuHand(hand);
  }

  /// Calibrated on exact counterfactual call values (3,475 first-Tichu
  /// decisions, heuristic self-play): -0.1 maximises the value of calls
  /// (+3.5 pts per decision; legacy rule -0.3) while players call 18.6 % of
  /// the time, i.e. ~34 % of rounds per team.
  static const double strengthThreshold = -0.1;

  /// Threshold when an opponent already called Tichu (best value +1.3 pts
  /// per decision at 4.4 % calls; lower thresholds lose up to -18).
  static const double strengthThresholdVsCall = 0.5;

  /// How likely [hand] goes out first: sure trick-winners (to take the lead
  /// back) against the number of plays the hand needs to go out.
  ///
  ///   winners = Dragon 1.0 + Phoenix 0.8 + 0.7 per Ace + 1.2 per bomb
  ///             + 0.2 per King
  ///   strength = winners - 0.35 * plays-to-go-out - 0.7 if holding the Dog
  static double tichuStrength(final List<Card> hand) {
    final shape = HandShape.fromCards(hand);
    double count(final CardFace f) =>
        hand.where((final c) => c.face == f).length.toDouble();
    final winners =
        count(CardFace.dragon) +
        0.8 * count(CardFace.phoenix) +
        0.7 * count(CardFace.ace) +
        1.2 * shape.bombs +
        0.2 * count(CardFace.king);
    return winners - 0.35 * shape.estPlays - 0.7 * count(CardFace.dog);
  }

  /// Whether [hand] is strong enough for the heuristic to call Tichu. Also
  /// used before the exchange to decide whether to keep strong cards.
  ///
  /// Besides the index, a Tichu hand needs at least [_minControls] controls
  /// (Dragon, Phoenix, Aces, bombs): exact counterfactual measurements showed
  /// calls with fewer controls lose ~20–30 points on average.
  ///
  /// The Dog or many low singles make a hand much harder to play out
  /// (measured: 36 % success with the Dog vs 65 % without; ~55 % with 4+
  /// unpaired cards below 10 vs ~70 % with 2), so such hands need one more
  /// control.
  bool isTichuHand(final List<Card> hand) => options.strictTichu
      ? tichuStrength(hand) >= strengthThreshold
      : _legacyTichuHand(hand);

  bool _legacyTichuHand(final List<Card> hand) {
    final hasDog = hand.any((final c) => c.face == CardFace.dog);
    final needed = options.strictTichu && (hasDog || _lowSingles(hand) >= 4)
        ? _minControls + 1
        : _minControls;
    return _tichuIndex(hand) >= _tichuIndexThreshold &&
        controlCount(hand) >= needed;
  }

  static const int _minControls = 3;

  /// Unpaired normal cards below ten.
  static int _lowSingles(final List<Card> hand) {
    final counts = <CardFace, int>{};
    for (final c in hand) {
      if (c.face == CardFace.dragon ||
          c.face == CardFace.phoenix ||
          c.face == CardFace.dog ||
          c.face == CardFace.mahJong) {
        continue;
      }
      counts[c.face] = (counts[c.face] ?? 0) + 1;
    }
    return counts.entries
        .where((final e) => e.value == 1 && Card.getValue(e.key) < 10)
        .length;
  }

  /// Dragon + Phoenix + Aces + bombs.
  static int controlCount(final List<Card> hand) =>
      hand
          .where(
            (final c) =>
                c.face == CardFace.dragon ||
                c.face == CardFace.phoenix ||
                c.face == CardFace.ace,
          )
          .length +
      getBombs(List<Card>.from(hand)).length;

  int _tichuIndex(final List<Card> hand) {
    final nAce = _countFace(hand, CardFace.ace);
    final nDog = _countFace(hand, CardFace.dog);
    final nDragon = _countFace(hand, CardFace.dragon);
    final nPhoenix = _countFace(hand, CardFace.phoenix);
    final nBomb = getBombs(List<Card>.from(hand)).length;
    final nStraight = getStraights(List<Card>.from(hand), 5).length;
    final nSmallSingleton = _smallSingletonCount(hand);

    return 2 * nAce -
        2 * nDog +
        6 * nDragon +
        6 * nPhoenix +
        5 * nBomb +
        nStraight -
        nSmallSingleton;
  }

  int _smallSingletonCount(final List<Card> hand) {
    final normalCards = hand
        .where(
          (final c) =>
              c.face != CardFace.dragon &&
              c.face != CardFace.phoenix &&
              c.face != CardFace.dog,
        )
        .toList();
    final occurrence = getOccurrenceCount(normalCards);
    var count = 0;
    for (final entry in occurrence.entries) {
      if (entry.value != 1) {
        continue;
      }
      final value = Card.getValue(entry.key);
      if (value >= 2 && value <= 7) {
        count += 1;
      }
    }
    return count;
  }

  int _countFace(final List<Card> hand, final CardFace face) =>
      hand.where((final card) => card.face == face).length;
}
