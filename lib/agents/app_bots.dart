import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:tichu/agents/bot_config.dart';
import 'package:tichu/agents/endgame_search.dart';
import 'package:tichu/agents/nn/belief_model.dart';
import 'package:tichu/agents/nn/wasm_mlp_kernel.dart';
import 'package:tichu/services/local/search_workers.dart';

/// The bots the app plays with. [load] is called once at startup; until
/// then (and in tests, or if loading fails) bots use the heuristic.
abstract final class AppBots {
  /// Trained play policy (rl/models/README.md): v10, schema v9 inputs.
  /// With [schupfAsset] and the belief search it beats the previous bot
  /// (v8 + schupf v4 + search <= 8) 63.7 %. Calls stay heuristic.
  static const playPolicyAsset = 'assets/bots/tichu_q_v10.safetensors';

  /// Learned schupf v5 (rl/schupf_cf_train.py) on the extended candidate
  /// set.
  static const schupfAsset = 'assets/bots/tichu_schupf_v5.safetensors';
  static const schupfExtended = true;

  /// Play-net scorer on wasm SIMD for the web (`web_kernel/`).
  static const kernelAsset = 'assets/bots/mlp_kernel.wasm';

  /// Card-location model (rl/belief_train.py): the endgame search re-deals
  /// its worlds with it instead of uniformly.
  static const beliefAsset = 'assets/bots/tichu_belief_v1.safetensors';

  /// Decision-time endgame search and one-on-one solver for the app bots
  /// (rl/README.md, "Search at decision time"). Flip to switch it off.
  /// ~70 ms per searched decision natively (more on phones and the web).
  static const useEndgameSearch = true;
  static const endgameSearch = EndgameSearch(
    maxCards: 12,
    solveOneOnOne: true,
    beliefWorlds: true,
  );

  static BotConfig current = BotConfig.heuristic;

  /// The searcher's card-location model; null until [load] (uniform worlds).
  static BeliefModel? belief;

  /// Workers that roll out the search's worlds with [current]'s bots
  /// (isolates natively, web workers in the browser); null = inline.
  static RolloutWorkers? searchWorkers;

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
      final beliefBytes = await rootBundle.load(beliefAsset);
      final kernelBytes = kIsWeb
          ? (await rootBundle.load(kernelAsset)).buffer.asUint8List()
          : null;
      final playScorer = kernelBytes == null
          ? null
          : await loadWasmScorer(kernelBytes);
      belief = BeliefModel(
        LoadedNet.fromBytes(beliefBytes.buffer.asUint8List()).network,
      );
      current = BotConfig(
        play: LoadedNet.fromBytes(play.buffer.asUint8List()),
        schupf: LoadedNet.fromBytes(schupf.buffer.asUint8List()),
        schupfExtended: schupfExtended,
        // Float32 SIMD (NEON on phones, SSE on desktop): ~3x faster, as
        // in the headless duels that evaluated these bots. On the web
        // Float32x4 is emulated and slower, so the web keeps float64.
        simdInference: !kIsWeb,
        // The web: float32 x4 in the wasm kernel (dart2js emulates
        // Float32x4); float64 in Dart where the browser lacks wasm SIMD.
        playScorer: playScorer,
        endgameSearch: useEndgameSearch ? endgameSearch : null,
      );
      searchWorkers = useEndgameSearch
          ? await startSearchWorkers(
              current,
              SearchWorkerAssets(
                playNet: play.buffer.asUint8List(),
                kernel: playScorer == null ? null : kernelBytes,
              ),
            )
          : null;
      // Loading must never stop the app from starting.
    } on Object {
      belief = null;
      searchWorkers = null;
      current = BotConfig.heuristic;
    }
  }
}
