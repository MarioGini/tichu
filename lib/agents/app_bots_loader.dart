import 'package:flutter/services.dart';

import 'package:tichu/agents/app_bots.dart';
import 'package:tichu/agents/bot_config.dart';

/// Loads [AppBots.playPolicyAsset] from the Flutter asset bundle.
Future<void> loadAppBotsFromAssets() async {
  try {
    final data = await rootBundle.load(AppBots.playPolicyAsset);
    AppBots.loadFromBytes(data.buffer.asUint8List());
    // Loading must never stop the app from starting.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    AppBots.current = BotConfig.heuristic;
  }
}
