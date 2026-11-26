// Entry point of the web's search worker (`web/search_worker.js`, built by
// `tool/build_web.sh`): rolls out endgame-search worlds for the page
// (`search_workers_web.dart`). Messages: an init array [init, play net
// bytes, wasm kernel bytes or null], answered with 'ready'; then JSON
// requests {id, worlds, actions, count, team}, answered with {id, values}.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:tichu/agents/bot_config.dart';
import 'package:tichu/agents/endgame_search.dart';
import 'package:tichu/agents/nn/wasm_mlp_kernel.dart';
import 'package:tichu/game/engine_state_codec.dart';

@JS('self')
external _Scope get _self;

extension type _Scope(JSObject _) implements JSObject {
  external JSFunction? get onmessage;
  external set onmessage(JSFunction? handler);
  external void postMessage(JSAny? message);
}

extension type _MessageEvent(JSObject _) implements JSObject {
  external JSAny? get data;
}

void main() {
  final bots = Completer<BotConfig>();
  // Requests run one at a time, in order.
  var queue = Future<void>.value();
  void onMessage(_MessageEvent event) {
    final data = event.data;
    if (data.isA<JSArray>()) {
      final init = (data! as JSArray).toDart;
      unawaited(
        _load(init[1]! as JSUint8Array, init[2] as JSUint8Array?).then((
          config,
        ) {
          bots.complete(config);
          _self.postMessage('ready'.toJS);
        }),
      );
      return;
    }
    final request =
        jsonDecode((data! as JSString).toDart) as Map<String, Object?>;
    queue = queue.then((_) async {
      final config = await bots.future;
      final values = await EndgameSearcher.rollOutWorlds(
        [
          for (final w in request['worlds']! as List)
            decodeEngineState(w as Map<String, Object?>),
        ],
        {
          for (final a in request['actions']! as List)
            (a as List)[0]! as int: decodeSearchAction(a[1]),
        },
        request['count']! as int,
        request['team']! as int,
        (id, _) => config.build(id),
      );
      _self.postMessage(
        jsonEncode({'id': request['id'], 'values': values}).toJS,
      );
    });
  }

  _self.onmessage = onMessage.toJS;
}

/// The page's rollout bots: its play net, scored by the wasm kernel when
/// the page uses it (the same config as `AppBots.current` for play).
Future<BotConfig> _load(JSUint8Array playNet, JSUint8Array? kernel) async {
  final kernelBytes = kernel?.toDart;
  final scorer = kernelBytes == null ? null : await loadWasmScorer(kernelBytes);
  return BotConfig(
    play: LoadedNet.fromBytes(playNet.toDart),
    playScorer: scorer,
  );
}
