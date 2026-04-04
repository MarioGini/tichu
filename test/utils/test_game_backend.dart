import 'dart:async';

import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';

class FakeGameBackend implements GameBackend {
  final StreamController<PlayerSnapshot> _controller =
      StreamController<PlayerSnapshot>.broadcast();
  final List<GameAction> actions = [];
  Duration? automatedActionDelay;
  PlayerSnapshot? _latestSnapshot;

  void emit(final PlayerSnapshot snapshot) {
    _latestSnapshot = snapshot;
    _controller.add(snapshot);
  }

  Future<void> close() async {
    await _controller.close();
  }

  @override
  Future<void> setAutomatedActionDelay(final Duration delay) async {
    automatedActionDelay = delay;
  }

  @override
  Stream<PlayerSnapshot> watchGame(
    final String gameId,
    final String playerId,
  ) async* {
    final latestSnapshot = _latestSnapshot;
    if (latestSnapshot != null) {
      yield latestSnapshot;
    }
    yield* _controller.stream;
  }

  @override
  Future<String> createGame(
    final List<GamePlayer> players, {
    final int targetScore = 1000,
  }) async => 'test-game';

  @override
  Future<void> startGame(final String gameId) async {}

  @override
  Future<void> startNewRound(final String gameId) async {}

  @override
  Future<void> submitAction(
    final String gameId,
    final GameAction action,
  ) async {
    actions.add(action);
  }

  @override
  Future<void> disposeGame(final String gameId) async {
    await close();
  }
}
