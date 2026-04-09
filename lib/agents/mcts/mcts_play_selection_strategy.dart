import 'dart:math';

import 'package:tichu/agents/mcts/belief_tracker.dart';
import 'package:tichu/agents/mcts/mcts_search.dart';
import 'package:tichu/agents/play_selection_strategy.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// Play selection strategy that uses Information Set MCTS (determinized
/// rollouts) to evaluate candidate moves.
///
/// For each legal play, it samples plausible opponent hands (constrained by
/// belief tracking of observed passes), simulates forward with heuristic
/// agents, and picks the move with the best average outcome.
///
/// Falls back to [DefaultPlaySelectionStrategy] when the hand is small enough
/// that search overhead isn't worth it.
class MctsPlaySelectionStrategy implements PlaySelectionStrategy {
  final String playerId;
  final int numDeterminizations;
  final int rolloutsPerDeterminization;
  final int minHandSizeForSearch;
  final PlaySelectionStrategy fallback;
  final Random? _random;
  final BeliefTracker beliefTracker = BeliefTracker();

  MctsPlaySelectionStrategy({
    required this.playerId,
    this.numDeterminizations = 20,
    this.rolloutsPerDeterminization = 1,
    this.minHandSizeForSearch = 3,
    this.fallback = const DefaultPlaySelectionStrategy(),
    final Random? random,
  }) : _random = random;

  /// Call this when any player passes to update beliefs.
  void recordPass({
    required final String passPlayerId,
    required final TichuTurn deckTurn,
  }) {
    beliefTracker.recordPass(playerId: passPlayerId, deckTurn: deckTurn);
  }

  @override
  TichuTurn selectPlay(
    final GameSnapshot snapshot,
    final List<TichuTurn> plays,
    final DeckState deck,
    final List<Card> hand,
  ) {
    // Update beliefs from snapshot metadata (schupf receipts, etc).
    beliefTracker.update(snapshot, playerId);

    if (plays.isEmpty) {
      throw ArgumentError.value(plays, 'plays', 'Must not be empty.');
    }

    // Single option or tiny hand — no point searching.
    if (plays.length == 1 || hand.length < minHandSizeForSearch) {
      return fallback.selectPlay(snapshot, plays, deck, hand);
    }

    // Convert TichuTurns into PlayTurnActions for the search.
    final candidates = <GameAction>[
      for (final play in plays)
        PlayTurnAction(
          playerId: playerId,
          cards: List<Card>.from(play.cards),
          inputWish: CardFace.none,
        ),
    ];

    final search = MctsSearch(
      numDeterminizations: numDeterminizations,
      rolloutsPerDeterminization: rolloutsPerDeterminization,
      random: _random,
    );

    final bestAction = search.search(
      snapshot: snapshot,
      playerId: playerId,
      candidates: candidates,
      beliefTracker: beliefTracker,
    );

    if (bestAction is PlayTurnAction) {
      for (final play in plays) {
        if (_cardsMatch(play.cards, bestAction.cards)) {
          return play;
        }
      }
    }

    return fallback.selectPlay(snapshot, plays, deck, hand);
  }

  bool _cardsMatch(final List<Card> a, final List<Card> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].face != b[i].face || a[i].color != b[i].color) {
        return false;
      }
    }
    return true;
  }
}
