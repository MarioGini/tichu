import 'dart:typed_data';

import 'package:tichu/agents/heuristic_options.dart';
import 'package:tichu/agents/nn/mlp.dart';
import 'package:tichu/agents/nn/nn_play_selection_strategy.dart';
import 'package:tichu/agents/nn/nn_schupf_strategy.dart';
import 'package:tichu/agents/nn/nn_tichu_call_strategy.dart';
import 'package:tichu/agents/play_selection_strategy.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/agents/tichu_call_strategy.dart';
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

  factory LoadedNet.fromBytes(final Uint8List bytes) {
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
  /// Play/pass policy (Q(s, a), `rl/bc_pretrain.py` / `rl/awr_train.py`).
  final LoadedNet? play;

  /// Tichu call-value net (`rl/call_train.py`).
  final LoadedNet? tichu;

  /// Grand Tichu call-value net (`rl/call_train.py`).
  final LoadedNet? grandTichu;

  /// Call-value net for Tichu before the schupf (`rl/call_train.py`).
  final LoadedNet? preSchupfTichu;

  /// Schupf value net (`rl/schupf_train.py`).
  final LoadedNet? schupf;

  /// Heuristic rules used for everything not covered by a learned net.
  final HeuristicOptions heuristicOptions;

  /// Required call advantage (round points) before calling (Grand) Tichu.
  final double callMargin;

  const BotConfig({
    this.play,
    this.tichu,
    this.grandTichu,
    this.preSchupfTichu,
    this.schupf,
    this.callMargin = 0,
    this.heuristicOptions = HeuristicOptions.latest,
  });

  /// The pure heuristic bot.
  static const heuristic = BotConfig();

  /// Build the agent for [playerId].
  ///
  /// [playOverride] replaces the play strategy (e.g. a search player such as
  /// ISMCTS in headless experiments) while keeping the other components.
  PlayerAgent build(
    final String playerId, {
    final PlaySelectionStrategy? playOverride,
  }) {
    final play = this.play;
    final schupf = this.schupf;
    return SmartAiAgent(
      playerId,
      options: heuristicOptions,
      playSelectionStrategy:
          playOverride ??
          (play == null
              ? null
              : NnPlaySelectionStrategy(
                  playerId: playerId,
                  network: play.network,
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
              fallback: DefaultTichuCallStrategy(options: heuristicOptions),
            ),
      schupfStrategy: schupf == null
          ? null
          : NnSchupfStrategy(network: schupf.network),
    );
  }
}
