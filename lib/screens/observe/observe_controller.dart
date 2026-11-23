import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tichu/agents/app_bots.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/record/game_record.dart';
import 'package:tichu/game/record/game_record_store.dart';
import 'package:tichu/game/record/recording_game_engine.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';
import 'package:tichu/services/local/ai_turn_runner.dart';
import 'package:tichu/services/local/local_match_runtime.dart';

/// What the observer can do next.
enum ObserveStep {
  /// Bots are still deciding (deal, schupf) — nothing to press.
  working,

  /// A bot has chosen its move; Continue applies it.
  move,

  /// The round is over; Continue deals the next one.
  roundOver,

  /// The match is over.
  gameOver,
}

/// Runs a match with four bots that pauses before every bot move, so a
/// person can watch it step by step. Every game is recorded to [store].
class ObserveController extends ChangeNotifier {
  ObserveController({
    this.store,
    final AgentFactory? agentFactory,
    this.targetScore = 1000,
    this.phaseDelay = const Duration(milliseconds: 250),
    this.botNames = const ['Bot 1', 'Bot 2', 'Bot 3', 'Bot 4'],
  }) : _agentFactory = agentFactory;

  final GameRecordStore? store;
  final AgentFactory? _agentFactory;
  final int targetScore;

  /// Pause between bots during the schupf (they are not stepped).
  final Duration phaseDelay;
  final List<String> botNames;

  late final RecordingGameEngine _engine = RecordingGameEngine(
    GameEngineImpl(),
    store: store,
    botDescription: AppBots.describe(),
    onSaved: (_, _) => _notify(),
  );
  late final LocalMatchRuntime _runtime = LocalMatchRuntime(
    engine: _engine,
    agentFactory: _agentFactory,
  );

  StreamSubscription<GameSnapshot>? _snapshotSub;
  StreamSubscription<GameRecord>? _recordSub;
  String? _gameId;
  GameSnapshot? _snapshot;
  bool _busy = false;
  bool _disposed = false;
  Object? _error;

  bool _autoPlay = false;
  Duration autoPlayInterval = const Duration(milliseconds: 1500);
  Timer? _autoTimer;
  int _followedSeat = 0;

  /// Auto-play speeds the viewer can pick: label and step interval.
  static const List<(String, Duration)> speeds = [
    ('0.5×', Duration(milliseconds: 3000)),
    ('1×', Duration(milliseconds: 1500)),
    ('2×', Duration(milliseconds: 750)),
    ('4×', Duration(milliseconds: 375)),
  ];

  String? get gameId => _gameId;
  GameSnapshot? get snapshot => _snapshot;
  GameRecord? get record =>
      _gameId == null ? null : _engine.recordFor(_gameId!);
  Object? get error => _error;
  bool get busy => _busy;
  bool get autoPlay => _autoPlay;

  /// Seat whose hand is shown face up at the bottom of the table.
  int get followedSeat => _followedSeat;

  /// Label of the current auto-play speed (see [speeds]).
  String get speedLabel {
    for (final (label, interval) in speeds) {
      if (interval == autoPlayInterval) return label;
    }
    final ms = autoPlayInterval.inMilliseconds;
    return ms <= 0 ? 'max' : '${(1500 / ms).toStringAsFixed(1)}×';
  }

  String? get recordLocation =>
      _gameId == null ? null : store?.describeLocation(_gameId!);

  ObserveStep get step {
    final s = _snapshot;
    if (s == null || _busy) return ObserveStep.working;
    if (s.scoreState.gameComplete) return ObserveStep.gameOver;
    if (s.scoreState.roundComplete) return ObserveStep.roundOver;
    if (s.opponentAwaitingConfirmation && s.pendingOpponentPlayerId != null) {
      return ObserveStep.move;
    }
    return ObserveStep.working;
  }

  bool get canContinue =>
      step == ObserveStep.move || step == ObserveStep.roundOver;

  /// Creates the match and deals the first round.
  Future<void> start() async {
    final players = [
      for (var seat = 0; seat < 4; seat++)
        GamePlayer(
          id: 'bot_${seat + 1}',
          name: botNames[seat],
          seat: seat,
          type: PlayerType.automated,
        ),
    ];
    await _runtime.setAutomatedActionDelay(phaseDelay);
    final gameId = await _runtime.createGame(players, targetScore: targetScore);
    _gameId = gameId;
    _snapshotSub = _runtime.watchGameState(gameId).listen((final s) {
      _snapshot = s;
      _notify();
    });
    _recordSub = _engine.watchRecord(gameId).listen((_) => _notify());
    await _guard(() => _runtime.startGame(gameId));
  }

  /// Applies the pending bot move, or deals the next round.
  Future<void> continueGame() async {
    final gameId = _gameId;
    final s = _snapshot;
    if (gameId == null || s == null || !canContinue) return;
    if (step == ObserveStep.roundOver) {
      await _guard(() => _runtime.startNewRound(gameId));
      return;
    }
    await _guard(
      () => _runtime.submitAction(
        gameId,
        ConfirmOpponentTurnAction(playerId: s.pendingOpponentPlayerId!),
      ),
    );
  }

  /// Steps automatically every [autoPlayInterval] (stops at round end).
  void setAutoPlay(final bool value) {
    _autoPlay = value;
    _scheduleAuto();
    _notify();
  }

  /// Shows [seat]'s hand at the bottom; the table rotates around it.
  void follow(final int seat) {
    if (seat == _followedSeat || seat < 0 || seat > 3) return;
    _followedSeat = seat;
    _notify();
  }

  /// Switches to the next auto-play speed (wraps around).
  void cycleSpeed() {
    final index = speeds.indexWhere((final s) => s.$2 == autoPlayInterval);
    autoPlayInterval = speeds[(index + 1) % speeds.length].$2;
    _scheduleAuto();
    _notify();
  }

  /// Waits until all pending record saves are written.
  Future<void> flushRecord() async {
    final id = _gameId;
    if (id != null) await _engine.flush(id);
  }

  Future<void> _guard(final Future<void> Function() body) async {
    _busy = true;
    _notify();
    try {
      await body();
      // Let the snapshot stream deliver the state the body produced.
      await Future<void>.delayed(Duration.zero);
      _error = null;
    } on Object catch (error) {
      _error = error;
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _scheduleAuto() {
    _autoTimer?.cancel();
    _autoTimer = null;
    if (!_autoPlay || step != ObserveStep.move) return;
    _autoTimer = Timer(autoPlayInterval, () {
      if (_autoPlay && step == ObserveStep.move) unawaited(continueGame());
    });
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
    if (_autoPlay && (_autoTimer == null || !_autoTimer!.isActive)) {
      _scheduleAuto();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _autoTimer?.cancel();
    unawaited(_snapshotSub?.cancel());
    unawaited(_recordSub?.cancel());
    final id = _gameId;
    if (id != null) {
      unawaited(_runtime.disposeGame(id));
      unawaited(_engine.forget(id));
    }
    super.dispose();
  }
}
