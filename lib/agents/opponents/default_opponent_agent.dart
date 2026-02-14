import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/opponent_agent.dart';
import 'package:tichu/game/scoring/score_tracker.dart';

class DefaultOpponentAgent extends SmartAiAgent implements OpponentAgent {
  DefaultOpponentAgent(
    super.playerId, {
    super.gameStateTracker,
    super.tichuCallStrategy,
    super.schupfStrategy,
    super.playSelectionStrategy,
    super.playTacticsPolicy,
    super.wishStrategy,
    super.dragonGiveStrategy,
  });

  @override
  Future<GameAction> selectAction(GameSnapshot snapshot) async {
    final canCallTichu = snapshot.canCallTichuByPlayer[playerId] ?? false;
    final tichuCall =
        snapshot.scoreState.tichuCalls[playerId] ?? TichuCall.none;
    if (canCallTichu && tichuCall == TichuCall.none) {
      final shouldCall = await shouldCallTichu(snapshot);
      if (shouldCall) {
        return CallTichuAction(playerId: playerId);
      }
    }

    return selectTurn(snapshot);
  }
}
