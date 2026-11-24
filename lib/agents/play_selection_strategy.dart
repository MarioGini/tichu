import 'package:tichu/agents/turn_scorer.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/turn/tichu_data.dart';

abstract class PlaySelectionStrategy {
  TichuTurn selectPlay(
    GameSnapshot snapshot,
    List<TichuTurn> plays,
    DeckState deck,
    List<Card> hand,
  );
}

/// A play strategy that decides the whole turn itself: any legal play or a
/// pass. `SmartAiAgent` then skips its tactical shortcuts (partner support
/// pass, lead tactics, singleton responses, ...) and only keeps the hard
/// rules (play out when possible, wish enforcement via `legalTurns`).
abstract interface class FullTurnPolicy {
  /// Returns the chosen play, or `null` to pass (only when [canPass]).
  TichuTurn? selectTurnOrPass(
    GameSnapshot snapshot,
    List<TichuTurn> legalTurns,
    DeckState deck,
    List<Card> hand, {
    required bool canPass,
  });
}

class DefaultPlaySelectionStrategy implements PlaySelectionStrategy {
  final TurnScorer turnScorer;

  const DefaultPlaySelectionStrategy({TurnScorer? turnScorer})
    : turnScorer = turnScorer ?? const TurnScorer();

  @override
  TichuTurn selectPlay(
    GameSnapshot snapshot,
    List<TichuTurn> plays,
    DeckState deck,
    List<Card> hand,
  ) {
    TichuTurn? bestPlay;
    var bestScore = double.negativeInfinity;

    for (final play in plays) {
      final score = turnScorer.scoreTurn(
        snapshot,
        snapshot.currentPlayerId,
        play,
        deck,
        hand,
      );
      if (score > bestScore) {
        bestScore = score;
        bestPlay = play;
      } else if (score == bestScore && bestPlay != null) {
        if (play.value < bestPlay.value) {
          bestPlay = play;
        }
      }
    }

    return bestPlay ?? plays.first;
  }
}
