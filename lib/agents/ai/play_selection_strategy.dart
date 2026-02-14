import 'package:tichu/game/game_backend.dart';
import 'package:tichu/agents/ai/turn_scorer.dart';
import 'package:tichu/game/turn/tichu_data.dart';

abstract class PlaySelectionStrategy {
  TichuTurn selectPlay(
    GameSnapshot snapshot,
    List<TichuTurn> plays,
    DeckState deck,
    List<Card> hand,
  );
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
