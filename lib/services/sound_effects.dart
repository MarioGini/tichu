import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class SoundEffects {
  static const String _dogAsset = 'assets/sfx/woof_woof.mp3';
  static const String _bombAsset = 'assets/sfx/bomb.mp3';

  static final AudioPlayer _player = AudioPlayer()
    ..setReleaseMode(ReleaseMode.stop);
  static Map<String, dynamic>? _assetManifest;

  static Future<void> playDog() async {
    await _playAsset(_dogAsset, SystemSoundType.click);
  }

  static Future<void> playBomb() async {
    await _playAsset(_bombAsset, SystemSoundType.alert);
  }

  static Future<void> _playAsset(
    String assetPath,
    SystemSoundType fallback,
  ) async {
    final assetKey = assetPath.replaceFirst('assets/', '');
    try {
      final exists = await _assetExists(assetPath);
      if (exists) {
        await _player.stop();
        await _player.play(AssetSource(assetKey));
        return;
      }
    } catch (_) {
      // Ignore and fall back to system sound.
    }

    SystemSound.play(fallback);
  }

  static Future<bool> _assetExists(String assetPath) async {
    if (_assetManifest == null) {
      final manifestString = await rootBundle.loadString('AssetManifest.json');
      _assetManifest = json.decode(manifestString) as Map<String, dynamic>;
    }
    return _assetManifest!.containsKey(assetPath);
  }
}
