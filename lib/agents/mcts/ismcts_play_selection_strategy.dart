import 'dart:math';

import 'package:tichu/agents/mcts/belief_tracker.dart';
import 'package:tichu/agents/mcts/ismcts_search.dart';
import 'package:tichu/agents/nn/mlp.dart';
import 'package:tichu/agents/play_selection_strategy.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// Play selection strategy using Information Set MCTS (IS-MCTS).
///
/// Wraps [IsmctsSearch] to integrate with [SmartAiAgent] via the
/// [PlaySelectionStrategy] interface. Maintains a [BeliefTracker] across
/// decisions to constrain hand sampling based on observed passes.
///
/// Supports optional value network for leaf evaluation instead of
/// heuristic rollouts.
class IsmctsPlaySelectionStrategy implements PlaySelectionStrategy {
  final String playerId;
  final int numSimulations;
  final double explorationConstant;
  final int minHandSizeForSearch;
  final PlaySelectionStrategy fallback;
  final Random? _random;
  final BeliefTracker beliefTracker = BeliefTracker();

  /// Optional neural network for leaf evaluation.
  final Mlp? valueNetwork;
  final double? valueNetworkMean;
  final double? valueNetworkStd;

  IsmctsPlaySelectionStrategy({
    required this.playerId,
    this.numSimulations = 100,
    this.explorationConstant = 1.4,
    this.minHandSizeForSearch = 3,
    this.fallback = const DefaultPlaySelectionStrategy(),
    this.valueNetwork,
    this.valueNetworkMean,
    this.valueNetworkStd,
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
    beliefTracker.update(snapshot, playerId);

    if (plays.isEmpty) {
      throw ArgumentError.value(plays, 'plays', 'Must not be empty.');
    }

    if (plays.length == 1 || hand.length < minHandSizeForSearch) {
      return fallback.selectPlay(snapshot, plays, deck, hand);
    }

    final candidates = <GameAction>[
      for (final play in plays)
        PlayTurnAction(
          playerId: playerId,
          cards: List<Card>.from(play.cards),
          inputWish: CardFace.none,
        ),
    ];

    final search = IsmctsSearch(
      numSimulations: numSimulations,
      explorationConstant: explorationConstant,
      valueNetwork: valueNetwork,
      valueNetworkMean: valueNetworkMean,
      valueNetworkStd: valueNetworkStd,
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
    final sortedA = [...a]..sort(compareCards);
    final sortedB = [...b]..sort(compareCards);
    for (var i = 0; i < sortedA.length; i++) {
      if (sortedA[i].face != sortedB[i].face ||
          sortedA[i].color != sortedB[i].color) {
        return false;
      }
    }
    return true;
  }
}
