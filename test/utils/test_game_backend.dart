import 'dart:async';

import 'package:tichu/services/game_backend.dart';

class FakeGameBackend implements GameBackend {
  final StreamController<PlayerSnapshot> _controller =
      StreamController<PlayerSnapshot>.broadcast();
  final List<GameAction> actions = [];

  void emit(PlayerSnapshot snapshot) => _controller.add(snapshot);

  Future<void> close() async {
    await _controller.close();
  }

  @override
  Stream<PlayerSnapshot> watchGame(String gameId, String playerId) {
    return _controller.stream;
  }

  @override
  Future<String> createGame(
    List<GamePlayer> players, {
    int targetScore = 1000,
  }) async {
    return 'test-game';
  }

  @override
  Future<void> startGame(String gameId) async {}

  @override
  Future<void> startNewRound(String gameId) async {}

  @override
  Future<void> submitAction(String gameId, GameAction action) async {
    actions.add(action);
  }

  @override
  Future<void> disposeGame(String gameId) async {
    await close();
  }
}
