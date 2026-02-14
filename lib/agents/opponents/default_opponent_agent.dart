import 'package:tichu/agents/ai/dragon_give_strategy.dart';
import 'package:tichu/agents/ai/game_state_tracker.dart';
import 'package:tichu/agents/ai/play_selection_strategy.dart';
import 'package:tichu/agents/ai/play_tactics_policy.dart';
import 'package:tichu/agents/ai/schupf_strategy.dart';
import 'package:tichu/agents/ai/smart_ai_agent.dart';
import 'package:tichu/agents/ai/tichu_call_strategy.dart';
import 'package:tichu/agents/ai/wish_strategy.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/scoring/score_tracker.dart';

import 'opponent_agent.dart';

class DefaultOpponentAgent extends SmartAiAgent implements OpponentAgent {
  DefaultOpponentAgent(
    super.playerId, {
    GameStateTracker? gameStateTracker,
    TichuCallStrategy? tichuCallStrategy,
    SchupfStrategy? schupfStrategy,
    PlaySelectionStrategy? playSelectionStrategy,
    PlayTacticsPolicy? playTacticsPolicy,
    WishStrategy? wishStrategy,
    DragonGiveStrategy? dragonGiveStrategy,
  }) : super(
         gameStateTracker: gameStateTracker,
         tichuCallStrategy: tichuCallStrategy,
         schupfStrategy: schupfStrategy,
         playSelectionStrategy: playSelectionStrategy,
         playTacticsPolicy: playTacticsPolicy,
         wishStrategy: wishStrategy,
         dragonGiveStrategy: dragonGiveStrategy,
       );

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
