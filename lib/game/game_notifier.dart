import 'package:flutter/foundation.dart';
import 'package:tichu/services/game_backend.dart';

/// UI-facing notifier API that can be backed by either a local or cloud backend.
///
/// Implementations should delegate to a [GameBackend] and expose the latest
/// [PlayerSnapshot] to the UI, calling [notifyListeners] on updates.
abstract class GameNotifier extends ChangeNotifier {
  /// The current snapshot of the game state (null until created).
  PlayerSnapshot? get snapshot;

  /// The game identifier once created.
  String? get gameId;

  /// True when a game has been created and a snapshot is available.
  bool get isReady;

  /// Creates a new game and begins listening for updates.
  Future<void> createGame(List<GamePlayer> players, {int targetScore = 1000});

  /// Starts the game lifecycle (e.g., initial deal / ready state).
  Future<void> startGame();

  /// Sends a game action (play, pass, tichu, schupf, etc.).
  Future<void> submitAction(GameAction action);

  /// Disposes any streams/resources held by the notifier.
  Future<void> disposeGame();
}
