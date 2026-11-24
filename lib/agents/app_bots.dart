import 'package:flutter/services.dart';

import 'package:tichu/agents/bot_config.dart';
import 'package:tichu/agents/endgame_search.dart';

/// The bots the app plays with. [load] is called once at startup; until
/// then (and in tests, or if loading fails) bots use the heuristic.
abstract final class AppBots {
  /// Trained play policy (rl/models/README.md): v8. With [schupfAsset] and
  /// the search it beats the previous bot (v7 + schupf v3) 61 %.
  /// Calls stay heuristic.
  static const playPolicyAsset = 'assets/bots/tichu_q_v8.safetensors';

  /// Learned schupf v4 (rl/schupf_cf_train.py), trained on v8's games.
  static const schupfAsset = 'assets/bots/tichu_schupf_v4.safetensors';

  /// Decision-time endgame search and one-on-one solver for the app bots
  /// (rl/README.md, "Search at decision time"). Flip to switch it off. With
  /// <= 8 cards in hand the search beats the same bot without it 57 %, at
  /// ~30 ms per searched decision natively (more on phones and the web).
  static const useEndgameSearch = true;
  static const endgameSearch = EndgameSearch(
    maxCards: 8,
    solveOneOnOne: true,
    solveBudget: 10000,
  );

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
