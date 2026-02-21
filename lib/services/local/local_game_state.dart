import 'dart:async';

import 'package:tichu/game/engine_state.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// Mutable state for a single local game session.
class LocalGameState {
  final GameEngineState engineState;
  final StreamController<GameSnapshot> controller;

  GameAction? pendingOpponentAction;
  String? pendingOpponentPlayerId;
  final List<Card> pendingOpponentCards = [];
  bool pendingOpponentPass = false;
  bool opponentAwaitingConfirmation = false;

  LocalGameState({required this.engineState})
    : controller = StreamController<GameSnapshot>.broadcast();
}
