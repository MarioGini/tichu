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

  test('headless rl-jsonl output writes transitions', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'tichu_headless_rl_jsonl_',
    );
    final outputFile = File('${tempDir.path}/episode.jsonl');

    try {
      await headless.main([
        '--seed=3',
        '--target-score=50',
        '--episodes=2',
        '--format=rl-jsonl',
        '--output=${outputFile.path}',
      ]);

      final lines = await outputFile.readAsLines();
      expect(lines, isNotEmpty);

      final first = jsonDecode(lines.first) as Map<String, dynamic>;
      expect(first['episode'], isA<int>());
      expect(first['seq'], isA<int>());
      expect(first['step'], isA<int>());
      expect(first['state_key'], isA<String>());
      expect(first['next_state_key'], isA<String>());
      expect(first['state'], isA<Map<String, dynamic>>());
      expect(first['next_state'], isA<Map<String, dynamic>>());
      expect(first['action'], isA<Map<String, dynamic>>());
      expect(first['action_key'], isA<String>());
      expect(first['legal_actions_enumerated'], isA<bool>());
      expect(first['player_id'], isA<String>());
      expect(first['action_type'], isA<String>());
      expect(first['reward'], isA<num>());
      expect(first['done'], isA<bool>());

      if (first['legal_actions_enumerated'] == true) {
        final legal = (first['legal_action_keys'] as List<dynamic>)
            .map((final item) => item.toString())
            .toSet();
        final actionKey = first['action_key'] as String;
        expect(legal.contains(actionKey), isTrue);
      }
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('headless runner accepts rl policy through AI interfaces', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'tichu_headless_rl_policy_',
    );
    final policyFile = File('${tempDir.path}/policy.json');
    final outputFile = File('${tempDir.path}/game.csv');

    await policyFile.writeAsString(
      jsonEncode(<String, Object?>{'state_action_values': <String, Object?>{}}),
    );

    try {
      await headless.main([
        '--seed=11',
        '--target-score=50',
        '--rounds=1',
        '--rl-policy=${policyFile.path}',
        '--output=${outputFile.path}',
      ]);

      expect(outputFile.existsSync(), isTrue);
      final lines = await outputFile.readAsLines();
      expect(lines, isNotEmpty);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
