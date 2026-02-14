import 'package:tichu/game/game_backend.dart';
import 'package:tichu/agents/ai/player_agent.dart';

abstract class OpponentAgent extends PlayerAgent {
  Future<GameAction> selectAction(GameSnapshot snapshot);
}
