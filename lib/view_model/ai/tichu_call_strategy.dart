import 'package:tichu/services/game_backend.dart';
import 'package:tichu/view_model/ai/hand_evaluator.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';

abstract class TichuCallStrategy {
  Future<bool> shouldCallGrandTichu(GameSnapshot snapshot, String playerId);
  Future<bool> shouldCallTichu(GameSnapshot snapshot, String playerId);
}

class DefaultTichuCallStrategy implements TichuCallStrategy {
  const DefaultTichuCallStrategy();

  @override
  Future<bool> shouldCallGrandTichu(
    GameSnapshot snapshot,
    String playerId,
  ) async {
    final hand = snapshot.hands[playerId] ?? const <Card>[];
    return HandEvaluator.shouldCallGrandTichu(hand);
  }

  @override
  Future<bool> shouldCallTichu(GameSnapshot snapshot, String playerId) async {
    final hand = snapshot.hands[playerId] ?? const <Card>[];
    return HandEvaluator.shouldCallTichu(hand);
  }
}
