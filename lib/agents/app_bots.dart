import 'package:flutter/services.dart';

import 'package:tichu/agents/bot_config.dart';

/// The bots the app plays with. [load] is called once at startup; until
/// then (and in tests, or if loading fails) bots use the heuristic.
abstract final class AppBots {
  /// Trained play policy (rl/models/README.md): rollout policy iteration on
  /// top of v3; beats v3 about 4 matches in 5. Tichu calls and schupf stay
  /// heuristic.
  static const playPolicyAsset = 'assets/bots/tichu_q_v4.safetensors';

  static BotConfig current = BotConfig.heuristic;

  /// Short description of the current bots, stored in game records.
  static String describe() => current.play != null
      ? 'play: $playPolicyAsset; calls, schupf, dragon: heuristic'
      : 'heuristic';

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
