import 'dart:typed_data';

import 'package:tichu/agents/bot_config.dart';

/// The bots the app plays with. Pure Dart so the authority server can use it;
/// the Flutter app loads the asset via `loadAppBotsFromAssets` in
/// `app_bots_loader.dart`. Until loaded (and in tests, or if loading fails)
/// bots use the heuristic.
abstract final class AppBots {
  /// Trained play policy (rl/models/README.md): ~71 % match win rate vs the
  /// heuristic. Tichu calls and schupf stay heuristic (they measured better).
  static const playPolicyAsset = 'assets/bots/tichu_q_v3.safetensors';

  static BotConfig current = BotConfig.heuristic;

  /// Installs the play policy from raw safetensors bytes; falls back to the
  /// heuristic if they cannot be parsed.
  static void loadFromBytes(final Uint8List bytes) {
    try {
      current = BotConfig(play: LoadedNet.fromBytes(bytes));
      // Loading must never stop the app or server from starting.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      current = BotConfig.heuristic;
    }
  }
}
