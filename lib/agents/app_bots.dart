import 'package:flutter/services.dart';

import 'package:tichu/agents/bot_config.dart';
import 'package:tichu/agents/endgame_search.dart';

/// The bots the app plays with. [load] is called once at startup; until
/// then (and in tests, or if loading fails) bots use the heuristic.
abstract final class AppBots {
  /// Trained play policy (rl/models/README.md): v7. With [schupfAsset] it
  /// beats the previous bot (v6 + schupf v2) 62 % and the heuristic 95 %.
  /// Calls stay heuristic.
  static const playPolicyAsset = 'assets/bots/tichu_q_v7.safetensors';

  /// Learned schupf v3 (rl/schupf_cf_train.py), trained on v7's games:
  /// v7 with it beats v7 with schupf v2 53 %.
  static const schupfAsset = 'assets/bots/tichu_schupf_v3.safetensors';

  /// Decision-time endgame search for the app bots (rl/README.md, "Endgame
  /// search"). Flip to switch it off.
  static const useEndgameSearch = true;
  static const endgameSearch = EndgameSearch();

  static BotConfig current = BotConfig.heuristic;

  /// Short description of the current bots, stored in game records.
  static String describe() => current.play != null
      ? 'play: $playPolicyAsset; schupf: $schupfAsset; '
            '${current.endgameSearch != null ? 'endgame search; ' : ''}'
            'calls, dragon: heuristic'
      : 'heuristic';

  static Future<void> load() async {
    try {
      final play = await rootBundle.load(playPolicyAsset);
      final schupf = await rootBundle.load(schupfAsset);
      current = BotConfig(
        play: LoadedNet.fromBytes(play.buffer.asUint8List()),
        schupf: LoadedNet.fromBytes(schupf.buffer.asUint8List()),
        endgameSearch: useEndgameSearch ? endgameSearch : null,
      );
      // Loading must never stop the app from starting.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      current = BotConfig.heuristic;
    }
  }
}
