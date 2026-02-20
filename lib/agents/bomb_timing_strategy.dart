import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/turn/tichu_data.dart';

abstract class BombTimingStrategy {
  bool shouldBomb(
    final GameSnapshot snapshot,
    final DeckState deck,
    final TichuTurn bomb,
    final List<Card> hand,
  );
}

class DefaultBombTimingStrategy implements BombTimingStrategy {
  const DefaultBombTimingStrategy();

  @override
  bool shouldBomb(
    final GameSnapshot snapshot,
    final DeckState deck,
    final TichuTurn bomb,
    final List<Card> hand,
  ) =>
    // Conservative default: allow bombs only when there are no non-bomb plays.
    false;
}
