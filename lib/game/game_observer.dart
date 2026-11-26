import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';

/// Told about every round start and every applied action of a game, e.g. an
/// agent that keeps its own record of what its seat has seen.
///
/// The snapshots hold every hand: an observer playing a seat must only pass
/// on what that seat may see.
abstract interface class GameObserver {
  /// A new round was dealt (first cards only, before the Grand Tichu calls).
  void roundStarted(GameSnapshot snapshot);

  void actionApplied(
    GameAction action,
    GameSnapshot before,
    GameSnapshot after,
  );
}
