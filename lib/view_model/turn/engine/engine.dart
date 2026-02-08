import 'package:tichu/services/game_backend.dart';
import 'package:tichu/view_model/turn/engine/engine_state.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';

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
    String? pendingAiPlayerId,
    List<Card>? pendingAiCards,
    bool pendingAiPass = false,
    bool aiAwaitingConfirmation = false,
  });

  PlayerSnapshot buildPlayerSnapshot(GameSnapshot snapshot, String playerId);

  bool hasPendingHumanSchupfReceipts(GameEngineState state);

  bool shouldPauseForAi(GameEngineState state, String actorId);

  List<String> opponentIds(GameEngineState state, String playerId);
}
