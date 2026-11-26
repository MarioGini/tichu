import 'dart:typed_data';

import 'package:tichu/agents/endgame_search.dart';
import 'package:tichu/agents/heuristic_options.dart';
import 'package:tichu/agents/nn/mlp.dart';
import 'package:tichu/agents/nn/nn_play_selection_strategy.dart';
import 'package:tichu/agents/nn/nn_schupf_strategy.dart';
import 'package:tichu/agents/nn/nn_tichu_call_strategy.dart';
import 'package:tichu/agents/nn/style_bias.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/player_agent.dart';

/// A loaded network plus the denormalisation from its safetensors metadata.
///
/// Platform-neutral (no `dart:io`): the app loads bytes from assets, the
/// headless runner from files.
class LoadedNet {
  final Mlp network;
  final double targetMean;
  final double targetStd;

  const LoadedNet(this.network, this.targetMean, this.targetStd);

  factory LoadedNet.fromBytes(Uint8List bytes) {
    final (net, mean, std) = Mlp.fromSafetensorsBytes(bytes);
    return LoadedNet(net, mean, std);
  }
}

/// Which learned components a bot uses. Every component is optional; a
/// missing one falls back to the heuristic.
///
/// This is the single way bots are built — by the app (`LocalMatchRuntime`
/// agent factory) and by the headless training runner — so a policy that is
/// trained and evaluated headlessly behaves the same in the app.
class BotConfig {
  /// Play/pass policy (Q(s, a), `rl/rollout_loop.py`).
  final LoadedNet? play;

  /// Tichu call-value net (`rl/call_train.py`).
  final LoadedNet? tichu;

  /// Grand Tichu call-value net (`rl/call_train.py`).
  final LoadedNet? grandTichu;

  /// Call-value net for Tichu before the schupf (`rl/call_train.py`).
  final LoadedNet? preSchupfTichu;

  /// Schupf value net (`rl/schupf_train.py`).
  final LoadedNet? schupf;

  /// The schupf net scores the extended candidate set (see
  /// [SchupfFeatures.candidates]).
  final bool schupfExtended;

  /// Heuristic rules used for everything not covered by a learned net.
  final HeuristicOptions heuristicOptions;

  /// Required call advantage (round points) before calling (Grand) Tichu.
  final double callMargin;

  /// Float32 SIMD inference for the play net: ~3x faster simulation when
  /// compiled ahead of time (headless runner, the app outside the web).
  final bool simdInference;

  /// Style experiment for the play net (headless `--style=`); none in the app.
  final StyleBias style;

  /// Decision-time endgame search (needs a play net and a driver that runs
  /// [EndgameSearcher]); null = off.
  final EndgameSearch? endgameSearch;

  /// Scorer for the play net instead of the Dart ones (the web: the wasm
  /// SIMD kernel, `WasmMlpKernel`); null = [simdInference] decides.
  final PrefixScorerFactory? playScorer;

  const BotConfig({
    this.play,
    this.tichu,
    this.grandTichu,
    this.preSchupfTichu,
    this.schupf,
    this.schupfExtended = false,
    this.callMargin = 0,
    this.simdInference = false,
    this.style = StyleBias.none,
    this.heuristicOptions = HeuristicOptions.latest,
    this.endgameSearch,
    this.playScorer,
  });

  /// This config with [search] as its endgame search (null = off).
  BotConfig withEndgameSearch(EndgameSearch? search) => BotConfig(
    play: play,
    tichu: tichu,
    grandTichu: grandTichu,
    preSchupfTichu: preSchupfTichu,
    schupf: schupf,
    schupfExtended: schupfExtended,
    callMargin: callMargin,
    simdInference: simdInference,
    style: style,
    heuristicOptions: heuristicOptions,
    endgameSearch: search,
    playScorer: playScorer,
  );

  /// The pure heuristic bot.
  static const heuristic = BotConfig();

  /// Build the agent for [playerId].
  PlayerAgent build(String playerId) {
    final play = this.play;
    final schupf = this.schupf;
    return SmartAiAgent(
      playerId,
      options: heuristicOptions,
      // The search needs the play net's moves to improve on.
      endgameSearch: play == null ? null : endgameSearch,
      playSelectionStrategy: (play == null
          ? null
          : NnPlaySelectionStrategy(
              playerId: playerId,
              network: play.network,
              simd: simdInference,
              scorerFactory: playScorer,
              style: style,
              outputScale: play.targetStd,
            )),
      tichuCallStrategy:
          tichu == null && grandTichu == null && preSchupfTichu == null
          ? null
          : NnTichuCallStrategy(
              tichuNetwork: tichu?.network,
              grandTichuNetwork: grandTichu?.network,
              tichuScale: tichu?.targetStd ?? 100,
              grandTichuScale: grandTichu?.targetStd ?? 100,
              preSchupfTichuNetwork: preSchupfTichu?.network,
              preSchupfTichuScale: preSchupfTichu?.targetStd ?? 100,
              margin: callMargin,
            ),
      schupfStrategy: schupf == null
          ? null
          : NnSchupfStrategy(network: schupf.network, extended: schupfExtended),
    );
  }
}
