import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class SoundEffects {
  static const String _dogAsset = 'assets/sfx/dog.mp3';
  static const String _bombAsset = 'assets/sfx/bomb.mp3';

  static AudioPlayer? _player;
  static Set<String>? _assetManifest;
  static bool _audioSupported = true;
  static bool _enabled = true;

  static bool get enabled => _enabled;

  // ignore: avoid_positional_boolean_parameters, simple toggle API
  static void setEnabled(final bool value) {
    _enabled = value;
    if (!value) {
      unawaited(_player?.stop());
    }
  }

  static Future<void> playDog() async {
    await _playAsset(_dogAsset, SystemSoundType.click);
  }

  static Future<void> playBomb() async {
    await _playAsset(_bombAsset, SystemSoundType.alert);
  }

  static Future<void> _playAsset(
    final String assetPath,
    final SystemSoundType fallback,
  ) async {
    if (!_enabled) {
      return;
    }

    final relativeAssetPath = assetPath.startsWith('assets/')
        ? assetPath.substring('assets/'.length)
        : assetPath;

    try {
      final exists = await _assetExists(assetPath);
      if (exists) {
        final player = await _getPlayer();
        if (player == null) {
          await SystemSound.play(fallback);
          return;
        }
        await player.stop();
        try {
          await player.play(AssetSource(relativeAssetPath));
        } on Object {
          await player.play(AssetSource(assetPath));
        }
        return;
      }
    } on Object catch (_) {
      // Ignore and fall back to system sound.
    }

    await SystemSound.play(fallback);
  }

  static Future<bool> _assetExists(final String assetPath) async {
    if (_assetManifest == null) {
      try {
        final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
        _assetManifest = manifest.listAssets().toSet();
      } on Object {
        _assetManifest = <String>{};
      }
    }
    return _assetManifest!.contains(assetPath);
  }

  static Future<AudioPlayer?> _getPlayer() async {
    if (!_audioSupported) {
      return null;
    }

    try {
      final player = _player ?? AudioPlayer();
      if (_player == null) {
        await player.setReleaseMode(ReleaseMode.stop);
        _player = player;
      }
      return _player;
    } on Object {
      _audioSupported = false;
      return null;
    }
  }
}
