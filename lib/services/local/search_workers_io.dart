import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:tichu/agents/bot_config.dart';
import 'package:tichu/agents/endgame_search.dart';
import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/services/local/search_workers.dart';

/// One worker per core, at most 4 (8 worlds: two each). The UI isolate
/// only waits while they work. Measured on 4 cores: 4 workers 31 ms per
/// searched decision, 3 workers 35 ms, inline 64-71 ms.
int get searchWorkerCount => min(4, Platform.numberOfProcessors);

Future<RolloutWorkers?> startSearchWorkers(
  BotConfig config,
  SearchWorkerAssets assets,
) async {
  final size = searchWorkerCount;
  return size < 2 ? null : IsolateRolloutWorkers(_rolloutBots(config), size);
}

/// Top level, so the closure captures only [config] (sent to isolates).
PlayerAgent Function(String, int) _rolloutBots(BotConfig config) =>
    (id, _) => config.build(id);

/// [size] long-lived isolates, each holding its own copy of the rollout
/// bots (sent once, when the first search starts them): a search sends
/// them only its worlds and actions. Spawning an isolate per search
/// (`Isolate.run`) copied the nets every time and was slower than one
/// isolate.
class IsolateRolloutWorkers implements RolloutWorkers {
  IsolateRolloutWorkers(this._agentFor, this.size);

  final PlayerAgent Function(String playerId, int seat) _agentFor;

  @override
  final int size;

  Future<List<_Worker>>? _workers;
  var _next = 0;

  Future<List<_Worker>> _start() =>
      Future.wait([for (var i = 0; i < size; i++) _Worker.spawn(_agentFor)]);

  @override
  Future<List<List<double?>>> rollOut(
    List<GameEngineState> worlds,
    Map<int, GameAction> actions,
    int count,
    int team,
  ) async {
    final workers = await (_workers ??= _start());
    return workers[_next++ % size].rollOut(worlds, actions, count, team);
  }

  /// Stops the isolates (tests); the next search starts new ones.
  Future<void> close() async {
    final workers = _workers;
    _workers = null;
    if (workers == null) return;
    for (final w in await workers) {
      w.close();
    }
  }
}

typedef _Request = (
  SendPort reply,
  List<GameEngineState> worlds,
  Map<int, GameAction> actions,
  int count,
  int team,
);

class _Worker {
  _Worker(this._isolate, this._requests, this._errors, this._errorPort);

  final Isolate _isolate;
  final SendPort _requests;

  /// Uncaught errors of the isolate (bugs): they fail the pending
  /// requests instead of leaving them waiting forever.
  final Stream<Object?> _errors;
  final ReceivePort _errorPort;

  static Future<_Worker> spawn(
    PlayerAgent Function(String playerId, int seat) agentFor,
  ) async {
    final ready = ReceivePort();
    final errorPort = ReceivePort();
    final isolate = await Isolate.spawn(
      _main,
      (ready.sendPort, agentFor),
      onError: errorPort.sendPort,
      debugName: 'search worker',
    );
    final requests = await ready.first as SendPort;
    return _Worker(isolate, requests, errorPort.asBroadcastStream(), errorPort);
  }

  Future<List<List<double?>>> rollOut(
    List<GameEngineState> worlds,
    Map<int, GameAction> actions,
    int count,
    int team,
  ) async {
    final reply = ReceivePort();
    _requests.send((reply.sendPort, worlds, actions, count, team));
    final failed = _errors.first.then<Object?>((error) {
      final [message, stack] = error! as List<Object?>;
      throw RemoteError('$message', '$stack');
    });
    final result = await Future.any([reply.first, failed]);
    reply.close();
    return result! as List<List<double?>>;
  }

  void close() {
    _errorPort.close();
    _isolate.kill(priority: Isolate.immediate);
  }

  static void _main(
    (SendPort, PlayerAgent Function(String playerId, int seat)) init,
  ) {
    final (ready, agentFor) = init;
    final requests = ReceivePort();
    ready.send(requests.sendPort);
    requests.listen((message) async {
      final (reply, worlds, actions, count, team) = message as _Request;
      reply.send(
        await EndgameSearcher.rollOutWorlds(
          worlds,
          actions,
          count,
          team,
          agentFor,
        ),
      );
    });
  }
}
