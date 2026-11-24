import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tichu/scoreboard/scoreboard_model.dart';

/// Keeps the scoreboard match in progress across app restarts.
abstract interface class ScoreboardStore {
  Future<ScoreboardGame?> loadCurrent();
  Future<void> saveCurrent(ScoreboardGame game);
  Future<void> clearCurrent();
}

class InMemoryScoreboardStore implements ScoreboardStore {
  InMemoryScoreboardStore([this._game]);

  ScoreboardGame? _game;

  @override
  Future<ScoreboardGame?> loadCurrent() async => _game;

  @override
  Future<void> saveCurrent(final ScoreboardGame game) async => _game = game;

  @override
  Future<void> clearCurrent() async => _game = null;
}

/// Local storage on the device (browser `localStorage` on web).
class SharedPreferencesScoreboardStore implements ScoreboardStore {
  static const _key = 'scoreboard.current';

  @override
  Future<ScoreboardGame?> loadCurrent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return ScoreboardGame.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
    } on Object catch (_) {
      // A corrupt or outdated entry must not lock the user out.
      return null;
    }
  }

  @override
  Future<void> saveCurrent(final ScoreboardGame game) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(game.toJson()));
  }

  @override
  Future<void> clearCurrent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
