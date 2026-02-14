import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/headless/headless.dart' as headless;

void main() {
  test('headless help exits without creating output', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'tichu_headless_help_',
    );
    final outputFile = File('${tempDir.path}/should_not_exist.csv');

    try {
      await headless.main(['--help', '--output=${outputFile.path}']);
      expect(await outputFile.exists(), isFalse);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

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

      final header = lines.first.split(',');
      final eventIndex = header.indexOf('event');
      final teamOneRoundIndex = header.indexOf('team_one_round');
      final teamTwoRoundIndex = header.indexOf('team_two_round');

      expect(eventIndex, isNonNegative);
      expect(teamOneRoundIndex, isNonNegative);
      expect(teamTwoRoundIndex, isNonNegative);

      final roundEndRows = lines
          .skip(1)
          .map((line) => line.split(','))
          .where(
            (columns) =>
                columns.length > teamTwoRoundIndex &&
                columns[eventIndex] == 'round_end',
          )
          .toList();

      expect(roundEndRows, isNotEmpty);

      for (final row in roundEndRows) {
        final teamOneRound = int.parse(row[teamOneRoundIndex]);
        final teamTwoRound = int.parse(row[teamTwoRoundIndex]);
        final roundTotal = teamOneRound + teamTwoRound;
        expect(
          roundTotal % 100,
          0,
          reason: 'Round total should be divisible by 100, got $roundTotal',
        );
      }
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('headless runner honors rounds argument', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'tichu_headless_rounds_',
    );
    final outputFile = File('${tempDir.path}/game.csv');

    try {
      await headless.main([
        '--seed=7',
        '--target-score=10000',
        '--rounds=3',
        '--output=${outputFile.path}',
      ]);

      final lines = await outputFile.readAsLines();
      expect(lines, isNotEmpty);

      final header = lines.first.split(',');
      final eventIndex = header.indexOf('event');
      expect(eventIndex, isNonNegative);

      final roundEndCount = lines
          .skip(1)
          .map((line) => line.split(','))
          .where(
            (columns) =>
                columns.length > eventIndex &&
                columns[eventIndex] == 'round_end',
          )
          .length;

      expect(roundEndCount, 3);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
