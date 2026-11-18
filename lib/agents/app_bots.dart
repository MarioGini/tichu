import 'package:flutter/services.dart';

import 'package:tichu/agents/bot_config.dart';

/// The bots the app plays with. [load] is called once at startup; until
/// then (and in tests, or if loading fails) bots use the heuristic.
abstract final class AppBots {
  /// Trained play policy (rl/models/README.md): v6, beats v5 60 % and the
  /// heuristic 94 %. Calls stay heuristic.
  static const playPolicyAsset = 'assets/bots/tichu_q_v6.safetensors';

  /// Learned schupf (rl/schupf_cf_train.py): with it v5 beat v5 with the
  /// first learned schupf 54 % (which beat the heuristic schupf 55 %).
  static const schupfAsset = 'assets/bots/tichu_schupf_v2.safetensors';

  static BotConfig current = BotConfig.heuristic;

  /// Short description of the current bots, stored in game records.
  static String describe() => current.play != null
      ? 'play: $playPolicyAsset; schupf: $schupfAsset; calls, dragon: heuristic'
      : 'heuristic';

  static Future<void> load() async {
    try {
      final play = await rootBundle.load(playPolicyAsset);
      final schupf = await rootBundle.load(schupfAsset);
      current = BotConfig(
        play: LoadedNet.fromBytes(play.buffer.asUint8List()),
        schupf: LoadedNet.fromBytes(schupf.buffer.asUint8List()),
      );
      // Loading must never stop the app from starting.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      current = BotConfig.heuristic;
    }
  }
}
