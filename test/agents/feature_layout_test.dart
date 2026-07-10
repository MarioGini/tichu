import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/nn/feature_encoder.dart';

/// Asserts that the Dart feature layout constants match the canonical
/// schema at `rl/schema/feature_spec.json`. This is the single contract
/// shared with the Python training side. If you edit the spec, this test
/// will tell you exactly which Dart constant drifted.
void main() {
  group('feature layout schema', () {
    late Map<String, dynamic> spec;
    late List<Map<String, dynamic>> groups;

    setUpAll(() {
      final file = File('rl/schema/feature_spec.json');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'rl/schema/feature_spec.json missing',
      );
      spec = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      groups = (spec['groups'] as List).cast<Map<String, dynamic>>();
    });

    test('schema version is current (v3)', () {
      expect(spec['version'], 3);
    });

    test('group sizes match listed feature names', () {
      for (final g in groups) {
        final size = g['size'] as int;
        final names = (g['features'] as List).cast<String>();
        expect(
          names.length,
          size,
          reason: "group '${g['name']}': size=$size but ${names.length} names",
        );
      }
    });

    int sizeOf(final String name) {
      return groups.firstWhere((final g) => g['name'] == name)['size'] as int;
    }

    test('Dart per-group counts match schema', () {
      expect(stateFeatureCount, sizeOf('state'));
      expect(handStructureFeatureCount, sizeOf('hand_structure'));
      expect(opponentFeatureCount, sizeOf('opponent'));
      expect(actionFeatureCount, sizeOf('action'));
    });

    test('Dart group offsets are contiguous and match schema order', () {
      var offset = 0;
      final expected = <String, int>{};
      for (final g in groups) {
        expected[g['name'] as String] = offset;
        offset += g['size'] as int;
      }
      expect(stateOffset, expected['state']);
      expect(handStructureOffset, expected['hand_structure']);
      expect(opponentOffset, expected['opponent']);
      expect(actionOffset, expected['action']);
    });

    test('Dart total feature count matches schema sum', () {
      final total = groups.fold<int>(
        0,
        (final acc, final g) => acc + (g['size'] as int),
      );
      expect(totalFeatureCount, total);
    });
  });
}
