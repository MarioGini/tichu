import 'package:flutter/services.dart';

import 'package:tichu/agents/bot_config.dart';

/// The bots the app plays with. [load] is called once at startup; until
/// then (and in tests, or if loading fails) bots use the heuristic.
abstract final class AppBots {
  /// Trained play policy (rl/models/README.md): ~71 % match win rate vs the
  /// heuristic. Tichu calls and schupf stay heuristic (they measured better).
  static const playPolicyAsset = 'assets/bots/tichu_q_v3.safetensors';

  static BotConfig current = BotConfig.heuristic;

  static Future<void> load() async {
    try {
      final data = await rootBundle.load(playPolicyAsset);
      current = BotConfig(play: LoadedNet.fromBytes(data.buffer.asUint8List()));
      // Loading must never stop the app from starting.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      current = BotConfig.heuristic;
    }
  }
}
