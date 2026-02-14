import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/scoring/score_tracker.dart';

/// Contract for any player driver — AI or manual.
///
/// The backend calls [selectAction] during the play phase as the single
/// entry-point.  The default implementation checks whether a tichu call
/// is available before delegating to [selectTurn].  Subclasses may
/// override [selectAction] for custom orchestration.
abstract class PlayerAgent {
  String get playerId;

  Future<bool> shouldCallGrandTichu(GameSnapshot snapshot);

  Future<bool> shouldCallTichu(GameSnapshot snapshot);

  Future<SchupfAction> selectSchupfCards(GameSnapshot snapshot);

  Future<GameAction> selectTurn(GameSnapshot snapshot);

  /// Selects which opponent (seat index) receives the dragon trick.
  int selectDragonGive(GameSnapshot snapshot);

  /// Play-phase entry-point called by the backend.
  ///
  /// The default implementation evaluates a tichu call before delegating
  /// to [selectTurn].  Override for custom pre-turn logic.
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
