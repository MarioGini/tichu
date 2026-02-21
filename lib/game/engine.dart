import 'package:tichu/game/engine_state.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/turn/tichu_data.dart';

export 'engine_state.dart';

abstract class GameEngine {
  GameEngineState createGame({
    required final String gameId,
    required final List<GamePlayer> players,
    final int targetScore = 1000,
  });

  void startNewRound(final GameEngineState state);

  void startGame(final GameEngineState state);

  void applyAction(final GameEngineState state, final GameAction action);

  GameSnapshot buildSnapshot(
    final GameEngineState state, {
    final String? pendingOpponentPlayerId,
    final List<Card>? pendingOpponentCards,
    final bool pendingOpponentPass = false,
    final bool opponentAwaitingConfirmation = false,
  });

  PlayerSnapshot buildPlayerSnapshot(
    final GameSnapshot snapshot,
    final String playerId,
  );

  bool hasPendingHumanSchupfReceipts(final GameEngineState state);

  bool shouldPauseForAutomatedOpponent(
    final GameEngineState state,
    final String actorId,
  );

  List<String> opponentIds(final GameEngineState state, final String playerId);
}
