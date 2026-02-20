import 'package:tichu/agents/turn_scorer.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/turn/tichu_data.dart';

abstract class PlaySelectionStrategy {
  TichuTurn selectPlay(
    final GameSnapshot snapshot,
    final List<TichuTurn> plays,
    final DeckState deck,
    final List<Card> hand,
  );
}

class DefaultPlaySelectionStrategy implements PlaySelectionStrategy {
  final TurnScorer turnScorer;

  const DefaultPlaySelectionStrategy({final TurnScorer? turnScorer})
    : turnScorer = turnScorer ?? const TurnScorer();

  @override
  TichuTurn selectPlay(
    final GameSnapshot snapshot,
    final List<TichuTurn> plays,
    final DeckState deck,
    final List<Card> hand,
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
