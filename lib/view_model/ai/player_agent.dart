import 'package:tichu/services/game_backend.dart';

abstract class PlayerAgent {
  String get playerId;

  Future<bool> shouldCallGrandTichu(GameSnapshot snapshot);

  Future<bool> shouldCallTichu(GameSnapshot snapshot);

  Future<SchupfAction> selectSchupfCards(GameSnapshot snapshot);

  Future<GameAction> selectTurn(GameSnapshot snapshot);

  /// Selects which opponent (seat index) receives the dragon trick.
  int selectDragonGive(GameSnapshot snapshot);
}
