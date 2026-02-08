import 'package:tichu/services/game_backend.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';

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
