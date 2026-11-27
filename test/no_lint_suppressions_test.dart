import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lints are never silenced (see AGENTS.md): fix the code instead. This
/// fails on suppression comments in the Dart and Python sources and on
/// rules turned off per diagnostic in the analyzer config.
void main() {
  final suppressions = {
    '.dart': RegExp(r'//\s*ignore(_for_file)?\s*:'),
    '.py': RegExp(r'#\s*(noqa|type:\s*ignore|pylint:\s*disable)'),
  };

  test('no lint suppression comments', () {
    final hits = <String>[];
    for (final dir in ['lib', 'test', 'tool', 'rl', 'arena/adapters']) {
      for (final entity in Directory(dir).listSync(recursive: true)) {
        if (entity is! File ||
            entity.path.contains('/.venv/') ||
            entity.path.contains('/target/')) {
          continue;
        }
        final dot = entity.path.lastIndexOf('.');
        final pattern = dot < 0
            ? null
            : suppressions[entity.path.substring(dot)];
        if (pattern == null) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (pattern.hasMatch(lines[i])) {
            hits.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }
    expect(hits, isEmpty, reason: 'Fix the code instead of silencing lints.');
  });

  test('no diagnostics downgraded to ignore in analysis_options.yaml', () {
    final config = File('analysis_options.yaml').readAsLinesSync();
    expect([
      for (final line in config)
        if (RegExp(r'^\s+\w+:\s*ignore\s*$').hasMatch(line)) line.trim(),
    ], isEmpty);
  });
}
