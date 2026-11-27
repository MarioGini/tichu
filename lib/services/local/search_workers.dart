import 'dart:typed_data';

import 'package:tichu/agents/bot_config.dart';
import 'package:tichu/agents/endgame_search.dart';
import 'package:tichu/services/local/search_workers_web.dart'
    if (dart.library.io) 'package:tichu/services/local/search_workers_io.dart'
    as impl;

/// The bots' nets as loaded, for workers that must load them themselves
/// (web workers share no Dart objects with the page).
class SearchWorkerAssets {
  const SearchWorkerAssets({required this.playNet, this.kernel});

  final Uint8List playNet;

  /// The wasm SIMD scorer (`assets/bots/mlp_kernel.wasm`), when used.
  final Uint8List? kernel;
}

/// Starts the workers of the app's endgame search for the bots of
/// [config]: isolates natively (one per core, at most 4), web workers in
/// the browser (`web/search_worker.js`, built by `tool/build_web.sh`).
/// Null when there is nothing to gain (one core) or the worker script
/// does not load; the search then runs on the UI isolate.
Future<RolloutWorkers?> startSearchWorkers(
  BotConfig config,
  SearchWorkerAssets assets,
) => impl.startSearchWorkers(config, assets);
