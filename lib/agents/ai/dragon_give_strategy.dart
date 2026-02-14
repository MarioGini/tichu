import 'package:tichu/game/game_backend.dart';
import 'package:tichu/agents/ai/table_relationships.dart';
import 'package:tichu/game/scoring/score_tracker.dart';

abstract class DragonGiveStrategy {
  int selectDragonGive(GameSnapshot snapshot, String playerId);
}

class DefaultDragonGiveStrategy implements DragonGiveStrategy {
  const DefaultDragonGiveStrategy();

  @override
  int selectDragonGive(GameSnapshot snapshot, String playerId) {
    final table = TableRelationships(snapshot, playerId);
    final leftSeat = table.leftSeat();
    final rightSeat = table.rightSeat();

    final leftPlayer = table.playerBySeat(leftSeat);
    final rightPlayer = table.playerBySeat(rightSeat);

    final tichuCalls = snapshot.scoreState.tichuCalls;
    final leftCall = tichuCalls[leftPlayer.id] ?? TichuCall.none;
    final rightCall = tichuCalls[rightPlayer.id] ?? TichuCall.none;

    if (leftCall != TichuCall.none && rightCall == TichuCall.none) {
      return rightSeat;
    }
    if (rightCall != TichuCall.none && leftCall == TichuCall.none) {
      return leftSeat;
    }

    final leftCards = (snapshot.hands[leftPlayer.id] ?? []).length;
    final rightCards = (snapshot.hands[rightPlayer.id] ?? []).length;

    if (leftCards >= rightCards) {
      return leftSeat;
    }
    return rightSeat;
  }
}
