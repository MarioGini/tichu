import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:tichu/agents/bot_config.dart';
import 'package:tichu/agents/endgame_search.dart';
import 'package:tichu/agents/nn/belief_model.dart';
import 'package:tichu/agents/nn/wasm_mlp_kernel.dart';
import 'package:tichu/agents/shipped_bots.dart';
import 'package:tichu/services/local/search_workers.dart';

/// The bots the app plays with ([ShippedBots]). [load] is called once at
/// startup; until then (and in tests, or if loading fails) bots use the
/// heuristic.
abstract final class AppBots {
  static BotConfig current = BotConfig.heuristic;

  /// The searcher's card-location model; null until [load] (uniform worlds).
  static BeliefModel? belief;

  /// Workers that roll out the search's worlds with [current]'s bots
  /// (isolates natively, web workers in the browser); null = inline.
  static RolloutWorkers? searchWorkers;

  /// Short description of the current bots, stored in game records.
  static String describe() => current.play != null
      ? 'play: ${ShippedBots.playPolicyAsset}; schupf: ${ShippedBots.schupfAsset}; '
            '${current.endgameSearch != null ? 'endgame search; ' : ''}'
            'calls, dragon: heuristic'
      : 'heuristic';

  static Future<void> load() async {
    try {
      final play = await rootBundle.load(ShippedBots.playPolicyAsset);
      final schupf = await rootBundle.load(ShippedBots.schupfAsset);
      final beliefBytes = await rootBundle.load(ShippedBots.beliefAsset);
      // The web: the play net's wasm SIMD kernel (`web_kernel/`).
      final kernelBytes = kIsWeb ? await fetchWasmKernel() : null;
      final playScorer = kernelBytes == null
          ? null
          : await loadWasmScorer(kernelBytes);
      belief = BeliefModel(
        LoadedNet.fromBytes(beliefBytes.buffer.asUint8List()).network,
      );
      current = BotConfig(
        play: LoadedNet.fromBytes(play.buffer.asUint8List()),
        schupf: LoadedNet.fromBytes(schupf.buffer.asUint8List()),
        schupfExtended: ShippedBots.schupfExtended,
        partnerConvention: ShippedBots.partnerConvention,
        // Float32 SIMD (NEON on phones, SSE on desktop): ~3x faster, as
        // in the headless duels that evaluated these bots. On the web
        // Float32x4 is emulated and slower, so the web keeps float64.
        simdInference: !kIsWeb,
        // The web: float32 x4 in the wasm kernel (dart2js emulates
        // Float32x4); float64 in Dart where the browser lacks wasm SIMD.
        playScorer: playScorer,
        endgameSearch: ShippedBots.useEndgameSearch
            ? ShippedBots.endgameSearch
            : null,
      );
      searchWorkers = ShippedBots.useEndgameSearch
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
