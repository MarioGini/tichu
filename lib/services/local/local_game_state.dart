import 'dart:async';

import 'package:tichu/game/engine_state.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// Mutable state for a single local game session.
class LocalGameState {
  final GameEngineState engineState;
  final StreamController<GameSnapshot> controller;
  GameSnapshot? latestSnapshot;

  GameAction? pendingOpponentAction;
  String? pendingOpponentPlayerId;
  final List<Card> pendingOpponentCards = [];
  bool pendingOpponentPass = false;
  bool opponentAwaitingConfirmation = false;

  LocalGameState({required this.engineState})
    : controller = StreamController<GameSnapshot>.broadcast();

  Stream<GameSnapshot> watchSnapshots() =>
      Stream<GameSnapshot>.multi((final streamController) {
        final current = latestSnapshot;
        if (current != null) {
          streamController.add(current);
        }

        final subscription = controller.stream.listen(
          streamController.add,
          onError: streamController.addError,
          onDone: streamController.close,
        );
        streamController.onCancel = subscription.cancel;
      }, isBroadcast: true);
}
