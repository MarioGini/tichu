import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/turn/tichu_data.dart';

abstract class BombTimingStrategy {
  bool shouldBomb(
    GameSnapshot snapshot,
    DeckState deck,
    TichuTurn bomb,
    List<Card> hand,
  );
}

class DefaultBombTimingStrategy implements BombTimingStrategy {
  const DefaultBombTimingStrategy();

  @override
  bool shouldBomb(
    GameSnapshot snapshot,
    DeckState deck,
    TichuTurn bomb,
    List<Card> hand,
  ) {
    // Conservative default: allow bombs only when there are no non-bomb plays.
    return false;
  }
}
