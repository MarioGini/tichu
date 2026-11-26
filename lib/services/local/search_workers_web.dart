import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:tichu/agents/bot_config.dart';
import 'package:tichu/agents/endgame_search.dart';
import 'package:tichu/game/engine.dart';
import 'package:tichu/game/engine_state_codec.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/services/local/search_workers.dart';

/// Built by `tool/build_web.sh` from `search_worker_main.dart`.
const searchWorkerScript = 'search_worker.js';

@JS('navigator.hardwareConcurrency')
external int? get _cores;

@JS('Worker')
extension type _Worker._(JSObject _) implements JSObject {
  external factory _Worker(String url);
  external void postMessage(JSAny? message);
  external JSFunction? get onmessage;
  external set onmessage(JSFunction? handler);
  external JSFunction? get onerror;
  external set onerror(JSFunction? handler);
  external void terminate();
}

extension type _MessageEvent(JSObject _) implements JSObject {
  external JSAny? get data;
}

extension type _ErrorEvent(JSObject _) implements JSObject {
  external String? get message;
}

Future<RolloutWorkers?> startSearchWorkers(
  BotConfig config,
  SearchWorkerAssets assets,
) async {
  // One per core, at most 4 (8 worlds: two each); the page only waits.
  final size = (_cores ?? 1).clamp(1, 4);
  if (size < 2) return null;
  final workers = [for (var i = 0; i < size; i++) _PoolWorker(assets)];
  final ready = await Future.wait([for (final w in workers) w.ready]);
  if (ready.every((ok) => ok)) return WebRolloutWorkers._(workers);
  // The script did not load (e.g. a dev build without it): search inline.
  for (final w in workers) {
    w.terminate();
  }
  return null;
}

/// Web workers running [EndgameSearcher.rollOutWorlds] with the bots of
/// the page's config (play net + wasm kernel, sent once); worlds and
/// actions go as JSON (`engine_state_codec.dart`).
class WebRolloutWorkers implements RolloutWorkers {
  WebRolloutWorkers._(this._workers);

  final List<_PoolWorker> _workers;
  var _next = 0;

  @override
  int get size => _workers.length;

  @override
  Future<List<List<double?>>> rollOut(
    List<GameEngineState> worlds,
    Map<int, GameAction> actions,
    int count,
    int team,
  ) => _workers[_next++ % size].rollOut(worlds, actions, count, team);
}

class _PoolWorker {
  _PoolWorker(SearchWorkerAssets assets)
    : _worker = _Worker(searchWorkerScript) {
    _worker
      ..onmessage = _onMessage.toJS
      ..onerror = _onError.toJS
      ..postMessage(
        <JSAny?>['init'.toJS, assets.playNet.toJS, assets.kernel?.toJS].toJS,
      );
  }

  final _Worker _worker;
  final Completer<bool> _ready = Completer();
  final Map<int, Completer<List<List<double?>>>> _pending = {};
  var _nextId = 0;

  /// True once the worker loaded its bots, false if its script failed.
  Future<bool> get ready => _ready.future;

  void terminate() => _worker.terminate();

  Future<List<List<double?>>> rollOut(
    List<GameEngineState> worlds,
    Map<int, GameAction> actions,
    int count,
    int team,
  ) {
    final id = _nextId++;
    final done = _pending[id] = Completer();
    _worker.postMessage(
      jsonEncode({
        'id': id,
        'worlds': [for (final w in worlds) encodeEngineState(w)],
        'actions': [
          for (final e in actions.entries) [e.key, encodeSearchAction(e.value)],
        ],
        'count': count,
        'team': team,
      }).toJS,
    );
    return done.future;
  }

  void _onMessage(_MessageEvent event) {
    final data = (event.data! as JSString).toDart;
    if (data == 'ready') {
      _ready.complete(true);
      return;
    }
    final reply = jsonDecode(data) as Map<String, Object?>;
    _pending.remove(reply['id']! as int)!.complete([
      for (final row in reply['values']! as List)
        [for (final v in row as List) (v as num?)?.toDouble()],
    ]);
  }

  /// The script failed to load (before ready) or a rollout threw (a bug):
  /// the pool is not used, or the waiting searches fail with the error.
  void _onError(_ErrorEvent event) {
    if (!_ready.isCompleted) {
      _ready.complete(false);
      return;
    }
    final error = StateError('search worker: ${event.message}');
    for (final p in _pending.values) {
      p.completeError(error);
    }
    _pending.clear();
  }
}
