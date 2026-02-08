import 'package:tichu/services/game_backend.dart';
import 'package:tichu/view_model/scoring/score_tracker.dart';

abstract class DragonGiveStrategy {
  int selectDragonGive(GameSnapshot snapshot, String playerId);
}

class DefaultDragonGiveStrategy implements DragonGiveStrategy {
  const DefaultDragonGiveStrategy();

  @override
  int selectDragonGive(GameSnapshot snapshot, String playerId) {
    final mySeat = _mySeat(snapshot, playerId);
    final leftSeat = (mySeat + 1) % 4;
    final rightSeat = (mySeat + 3) % 4;

    final leftPlayer = snapshot.players.firstWhere((p) => p.seat == leftSeat);
    final rightPlayer = snapshot.players.firstWhere((p) => p.seat == rightSeat);

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

  int _mySeat(GameSnapshot snapshot, String playerId) {
    return snapshot.players.firstWhere((p) => p.id == playerId).seat;
  }
}
