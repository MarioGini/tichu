import 'dart:math';

import 'package:tichu/agents/mcts/belief_tracker.dart';
import 'package:tichu/game/card_identifiers.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/turn/move_generator.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// Samples plausible opponent hands consistent with observed information.
///
/// Uses two layers of constraint:
///   1. **Hard**: cards in our hand and cards visibly played are excluded.
///   2. **Belief**: if an opponent passed on a trick, reject samples where
///      that opponent's hand could have beaten it (they would have played).
///
/// Uses rejection sampling: draw a uniform deal, check constraints, retry if
/// violated. Falls back to unconstrained after [maxRetries] to avoid hanging.
class HandSampler {
  final Random _random;
  static const _maxRetries = 50;

  HandSampler({final Random? random}) : _random = random ?? Random();

  /// Build the set of all 56 cards in the Tichu deck.
  static List<Card> get fullDeck => cardIdentifiers.values.toList();

  /// Compute which cards are unaccounted for (not in our hand, not played).
  static List<Card> unknownCards({
    required final List<Card> myHand,
    required final List<Card> playedCards,
  }) {
    final known = <(CardFace, CardColor)>{};
    for (final card in myHand) {
      known.add((card.face, card.color));
    }
    for (final card in playedCards) {
      known.add((card.face, card.color));
    }

    return fullDeck
        .where((final card) => !known.contains((card.face, card.color)))
        .toList();
  }

  /// Collect all cards that have been played and are visible.
  static List<Card> visiblePlayedCards(final GameSnapshot snapshot) {
    final played = <Card>[];
    played.addAll(snapshot.deck.turn.cards);
    played.addAll(snapshot.deck.cardStack);
    return played;
  }

  /// Sample one plausible world, optionally constrained by beliefs.
  ///
  /// If [beliefTracker] is provided, uses rejection sampling to discard
  /// deals where an opponent could have beaten a trick they passed on.
  Map<String, List<Card>> sampleHands({
    required final GameSnapshot snapshot,
    required final String myPlayerId,
    final BeliefTracker? beliefTracker,
  }) {
    final myHand = snapshot.hands[myPlayerId] ?? const <Card>[];
    final played = visiblePlayedCards(snapshot);
    final unknown = unknownCards(myHand: myHand, playedCards: played);

    final opponentIds = snapshot.hands.keys
        .where((final id) => id != myPlayerId)
        .toList();
    final opponentCounts = {
      for (final id in opponentIds) id: snapshot.hands[id]?.length ?? 0,
    };

    // Precompute known-held cards per opponent from beliefs.
    final knownHeld = <String, Set<(CardFace, CardColor)>>{};
    if (beliefTracker != null) {
      for (final id in opponentIds) {
        knownHeld[id] = beliefTracker.knownHeldBy(id);
      }
    }

    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      final deal = _dealUnknown(
        unknown: unknown,
        opponentIds: opponentIds,
        opponentCounts: opponentCounts,
        knownHeld: knownHeld,
      );

      if (beliefTracker == null || _satisfiesBeliefs(deal, beliefTracker)) {
        deal[myPlayerId] = List<Card>.from(myHand);
        return deal;
      }
    }

    // Fallback: return unconstrained deal.
    final fallback = _dealUnknown(
      unknown: unknown,
      opponentIds: opponentIds,
      opponentCounts: opponentCounts,
      knownHeld: knownHeld,
    );
    fallback[myPlayerId] = List<Card>.from(myHand);
    return fallback;
  }

  /// Deal unknown cards to opponents, respecting known-held constraints.
  Map<String, List<Card>> _dealUnknown({
    required final List<Card> unknown,
    required final List<String> opponentIds,
    required final Map<String, int> opponentCounts,
    required final Map<String, Set<(CardFace, CardColor)>> knownHeld,
  }) {
    final pool = List<Card>.from(unknown);

    // First, extract known-held cards and assign them to their owners.
    final deal = <String, List<Card>>{};
    final usedFromPool = <int>{};

    for (final id in opponentIds) {
      deal[id] = <Card>[];
      final known = knownHeld[id];
      if (known == null || known.isEmpty) continue;

      for (final cardId in known) {
        final idx = pool.indexWhere(
          (final c) =>
              c.face == cardId.$1 &&
              c.color == cardId.$2 &&
              !usedFromPool.contains(pool.indexOf(c)),
        );
        if (idx >= 0 && !usedFromPool.contains(idx)) {
          deal[id]!.add(pool[idx]);
          usedFromPool.add(idx);
        }
      }
    }

    // Build remaining pool (exclude already-assigned cards).
    final remaining = <Card>[];
    for (var i = 0; i < pool.length; i++) {
      if (!usedFromPool.contains(i)) {
        remaining.add(pool[i]);
      }
    }
    remaining.shuffle(_random);

    // Fill each opponent to their expected count.
    var offset = 0;
    for (final id in opponentIds) {
      final need = opponentCounts[id]! - deal[id]!.length;
      if (need <= 0) continue;
      final take = need.clamp(0, remaining.length - offset);
      deal[id]!.addAll(remaining.sublist(offset, offset + take));
      offset += take;
    }

    return deal;
  }

  /// Check if a deal is consistent with observed pass behavior.
  ///
  /// For each opponent, verify that their sampled hand could NOT have beaten
  /// the tricks they actually passed on. If a sampled hand has a legal play
  /// that beats a passed trick, the deal is rejected.
  bool _satisfiesBeliefs(
    final Map<String, List<Card>> deal,
    final BeliefTracker beliefTracker,
  ) {
    for (final entry in deal.entries) {
      final playerId = entry.key;
      final hand = entry.value;
      final constraints = beliefTracker.constraintsFor(playerId);
      if (constraints.isEmpty) continue;

      for (final constraint in constraints) {
        final syntheticDeck = DeckState(
          _syntheticTurn(
            constraint.deckType,
            constraint.deckValue,
            constraint.deckCardCount,
          ),
          CardFace.none,
        );

        final legalBeats = generateLegalTurns(
          syntheticDeck,
          List<Card>.from(hand),
        );

        // If the sampled hand could have beaten this trick, but the real
        // player passed, this deal is inconsistent.
        if (legalBeats.isNotEmpty) {
          return false;
        }
      }
    }
    return true;
  }

  /// Create a minimal TichuTurn with the right type, value, and card count
  /// for legal move generation checks.
  static TichuTurn _syntheticTurn(
    final TurnType type,
    final double value,
    final int cardCount,
  ) {
    // generateLegalTurns checks deck.turn.type, deck.turn.value, and
    // deck.turn.cards.length (for straights/pair straights).
    // We need placeholder cards with the right count.
    final cards = List<Card>.generate(
      cardCount,
      (final _) => Card(CardFace.none, CardColor.special),
    );
    return _FixedValueTurn(type, cards, value);
  }
}

/// A TichuTurn with an explicitly set value (bypassing the normal calculation).
class _FixedValueTurn extends TichuTurn {
  @override
  final double value;

  _FixedValueTurn(super.type, super.cards, this.value);
}
