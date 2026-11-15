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

  /// The heuristic only calls Tichu once the exchange is done.
  @override
  Future<bool> shouldCallTichuBeforeSchupf(
    final GameSnapshot snapshot,
    final String playerId,
  ) async => false;

  const DefaultTichuCallStrategy();

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
    return !opponentCalled && isTichuHand(hand);
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
  bool isTichuHand(final List<Card> hand) {
    final hasDog = hand.any((final c) => c.face == CardFace.dog);
    final needed = hasDog || _lowSingles(hand) >= 4
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
