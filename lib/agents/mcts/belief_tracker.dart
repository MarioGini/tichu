import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// Tracks observed pass events to constrain what opponents can plausibly hold.
///
/// When a player passes on a trick, we infer they had no legal play that beats
/// the current deck. This lets us reject sampled hands that would have had a
/// winning play at a point where the real player passed.
///
/// This is the core of **belief-based** hand sampling for imperfect-info search
/// (used in strong Bridge/Skat/Hearts programs).
class BeliefTracker {
  int _lastRoundNumber = 0;

  /// Recorded pass constraints: for each player, the list of deck states where
  /// they passed (meaning they couldn't/didn't beat it).
  final Map<String, List<PassConstraint>> _passConstraints = {};

  /// Cards known to be held by a specific player (e.g. from schupf).
  final Map<String, Set<(CardFace, CardColor)>> _knownHeld = {};

  void reset() {
    _passConstraints.clear();
    _knownHeld.clear();
  }

  /// Update beliefs from the current snapshot. Call this every time the
  /// snapshot changes.
  void update(final GameSnapshot snapshot, final String myPlayerId) {
    if (_lastRoundNumber != snapshot.scoreState.roundNumber) {
      _lastRoundNumber = snapshot.scoreState.roundNumber;
      reset();
    }

    // Track schupf receipts — we know exactly which cards went to whom.
    for (final entry in snapshot.schupfReceipts.entries) {
      if (entry.key == myPlayerId) continue;
      for (final receipt in entry.value) {
        _knownHeld.putIfAbsent(entry.key, () => <(CardFace, CardColor)>{}).add((
          receipt.card.face,
          receipt.card.color,
        ));
      }
    }
  }

  /// Record that [playerId] passed when the deck showed [deckTurn].
  /// This means their hand (at that moment) couldn't beat this turn,
  /// or they had no bombs to interrupt.
  void recordPass({
    required final String playerId,
    required final TichuTurn deckTurn,
  }) {
    // Only meaningful if there's an active trick to beat.
    if (deckTurn.type == TurnType.empty ||
        deckTurn.type == TurnType.none ||
        deckTurn.type == TurnType.dog) {
      return;
    }

    _passConstraints
        .putIfAbsent(playerId, () => <PassConstraint>[])
        .add(
          PassConstraint(
            deckType: deckTurn.type,
            deckValue: deckTurn.value,
            deckCardCount: deckTurn.cards.length,
          ),
        );
  }

  /// Get pass constraints for a player.
  List<PassConstraint> constraintsFor(final String playerId) =>
      _passConstraints[playerId] ?? const [];

  /// Get cards known to be held by a player.
  Set<(CardFace, CardColor)> knownHeldBy(final String playerId) =>
      _knownHeld[playerId] ?? const {};
}

/// A constraint from an observed pass: the player couldn't beat this trick.
class PassConstraint {
  final TurnType deckType;
  final double deckValue;
  final int deckCardCount;

  const PassConstraint({
    required this.deckType,
    required this.deckValue,
    required this.deckCardCount,
  });
}
