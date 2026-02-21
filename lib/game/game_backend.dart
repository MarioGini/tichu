import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';

abstract class GameBackend {
  Stream<PlayerSnapshot> watchGame(final String gameId, final String playerId);

  Future<void> setAutomatedActionDelay(final Duration delay);

  Future<String> createGame(
    final List<GamePlayer> players, {
    final int targetScore = 1000,
  });

  Future<void> startGame(final String gameId);

  Future<void> startNewRound(final String gameId);

  Future<void> submitAction(final String gameId, final GameAction action);

  Future<void> disposeGame(final String gameId);
}
