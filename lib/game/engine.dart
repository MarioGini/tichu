import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/engine_state.dart';
import 'package:tichu/game/turn/tichu_data.dart';

export 'engine_state.dart';

abstract class GameEngine {
  GameEngineState createGame({
    required String gameId,
    required List<GamePlayer> players,
    int targetScore = 1000,
  });

  void startNewRound(GameEngineState state);

  void startGame(GameEngineState state);

  void applyAction(GameEngineState state, GameAction action);

  GameSnapshot buildSnapshot(
    GameEngineState state, {
    String? pendingOpponentPlayerId,
    List<Card>? pendingOpponentCards,
    bool pendingOpponentPass = false,
    bool opponentAwaitingConfirmation = false,
  });

  PlayerSnapshot buildPlayerSnapshot(GameSnapshot snapshot, String playerId);

  bool hasPendingHumanSchupfReceipts(GameEngineState state);

  bool shouldPauseForAutomatedOpponent(GameEngineState state, String actorId);

  List<String> opponentIds(GameEngineState state, String playerId);
}
