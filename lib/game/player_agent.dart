import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// Contract for any player driver — AI or manual.
///
/// The backend calls [selectAction] during the play phase as the single
/// entry-point.  The default implementation checks whether a tichu call
/// is available before delegating to [selectTurn].  Subclasses may
/// override [selectAction] for custom orchestration.
abstract class PlayerAgent {
  String get playerId;

  Future<bool> shouldCallGrandTichu(final GameSnapshot snapshot);

  Future<bool> shouldCallTichu(final GameSnapshot snapshot);

  /// Whether to call Tichu during the schupf phase, before passing cards.
  /// Defaults to no.
  Future<bool> shouldCallTichuBeforeSchupf(final GameSnapshot snapshot) async =>
      false;

  Future<SchupfAction> selectSchupfCards(final GameSnapshot snapshot);

  Future<GameAction> selectTurn(final GameSnapshot snapshot);

  /// Out of turn: the cards of one of [bombs] (all beat the trick on the
  /// table) to bomb now, or null to wait. Defaults to never.
  Future<List<Card>?> selectInterruptBomb(
    final GameSnapshot snapshot,
    final List<TichuTurn> bombs,
  ) async => null;

  /// Selects which opponent (seat index) receives the dragon trick.
  int selectDragonGive(final GameSnapshot snapshot);

  /// Play-phase entry-point called by the backend.
  ///
  /// The default implementation evaluates a tichu call before delegating
  /// to [selectTurn].  Override for custom pre-turn logic.
  Future<GameAction> selectAction(final GameSnapshot snapshot) async {
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
