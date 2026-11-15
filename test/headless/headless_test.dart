import 'dart:convert';
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
      expect(outputFile.existsSync(), isFalse);
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
          .map((final line) => line.split(','))
          .where(
            (final columns) =>
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
          .map((final line) => line.split(','))
          .where(
            (final columns) =>
                columns.length > eventIndex &&
                columns[eventIndex] == 'round_end',
          )
          .length;

      expect(roundEndCount, 3);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('headless runner stays stable for longer round batches', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'tichu_headless_stability_',
    );
    final outputFile = File('${tempDir.path}/game.csv');

    try {
      await headless.main([
        '--seed=1',
        '--target-score=100000',
        '--rounds=10',
        '--output=${outputFile.path}',
      ]);

      final lines = await outputFile.readAsLines();
      expect(lines, isNotEmpty);

      final header = lines.first.split(',');
      final eventIndex = header.indexOf('event');
      expect(eventIndex, isNonNegative);

      final roundEndCount = lines
          .skip(1)
          .map((final line) => line.split(','))
          .where(
            (final columns) =>
                columns.length > eventIndex &&
                columns[eventIndex] == 'round_end',
          )
          .length;

      expect(roundEndCount, 10);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'headless bc-jsonl output writes minimal training transitions',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'tichu_headless_bc_jsonl_',
      );
      final outputFile = File('${tempDir.path}/episode.jsonl');

      try {
        await headless.main([
          '--seed=3',
          '--target-score=50',
          '--episodes=2',
          '--format=bc-jsonl',
          '--output=${outputFile.path}',
        ]);

        final lines = await outputFile.readAsLines();
        expect(lines, isNotEmpty);

        final first = jsonDecode(lines.first) as Map<String, dynamic>;
        expect(first['episode'], isA<int>());
        expect(first['team'], isA<int>());
        expect(first['state_features'], isA<List<dynamic>>());
        expect((first['state_features'] as List).length, 46);
        expect(first['legal_play_action_features'], isA<List<dynamic>>());
        final legal = first['legal_play_action_features'] as List;
        expect(legal.length, greaterThanOrEqualTo(2));
        expect((legal.first as List).length, 20);
        expect(first['legal_play_chosen_index'], isA<int>());
        final chosen = first['legal_play_chosen_index'] as int;
        expect(chosen, greaterThanOrEqualTo(0));
        expect(chosen, lessThan(legal.length));
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );

  test('headless summary output writes one line per match', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'tichu_headless_summary_',
    );
    final outputFile = File('${tempDir.path}/eval.jsonl');

    try {
      await headless.main([
        '--seed=4',
        '--target-score=50',
        '--episodes=3',
        '--format=summary',
        '--output=${outputFile.path}',
      ]);

      final lines = await outputFile.readAsLines();
      expect(lines.length, 3);
      for (final line in lines) {
        final row = jsonDecode(line) as Map<String, dynamic>;
        expect(row['episode'], isA<int>());
        expect(row['team_one_total'], isA<int>());
        expect(row['team_two_total'], isA<int>());
        expect(row['done'], isA<bool>());
      }
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
