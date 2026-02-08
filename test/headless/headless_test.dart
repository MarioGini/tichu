import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../headless/headless.dart' as headless;

void main() {
  test('headless runner writes a playable log', () async {
    final tempDir = await Directory.systemTemp.createTemp('tichu_headless_');
    final outputFile = File('${tempDir.path}/game.csv');

    try {
      await headless.main([
        '--seed=1',
        '--target-score=50',
        '--output=${outputFile.path}',
      ]);

      final lines = await outputFile.readAsLines();

      expect(lines, isNotEmpty);
      expect(lines.first, startsWith('seq,ts_ms,game_id,round,phase,event,'));
      expect(lines.length, greaterThan(1));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
