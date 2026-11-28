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

    test('schema version is current (v10)', () {
      expect(spec['version'], 10);
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
        expect(
          names.toSet().length,
          names.length,
          reason: "group '${g['name']}' has duplicate feature names",
        );
      }
    });

    test('Dart groups match schema order, sizes and offsets', () {
      final dart = <(String, int, int)>[
        ('hand', handOffset, handFeatureCount),
        ('played', playedOffset, playedFeatureCount),
        ('unseen', unseenOffset, unseenFeatureCount),
        ('trick', trickOffset, trickFeatureCount),
        ('seats', seatsOffset, seatsFeatureCount),
        ('self', selfOffset, selfFeatureCount),
        ('hand_structure', handStructureOffset, handStructureFeatureCount),
        ('history', historyOffset, historyFeatureCount),
        ('turn', turnOffset, turnFeatureCount),
        ('claim', claimOffset, claimFeatureCount),
        ('received', receivedOffset, receivedRankFeatureCount),
        ('passed', passedOffset, passedRankFeatureCount),
        ('convention', conventionOffset, conventionFeatureCount),
        ('action', actionOffset, actionFeatureCount),
      ];
      expect(
        groups.map((g) => g['name']).toList(),
        dart.map((d) => d.$1).toList(),
      );
      var offset = 0;
      for (var i = 0; i < groups.length; i++) {
        final (name, dartOffset, dartSize) = dart[i];
        expect(dartOffset, offset, reason: '$name offset');
        expect(dartSize, groups[i]['size'], reason: '$name size');
        offset += groups[i]['size'] as int;
      }
      expect(stateFeatureCount, actionOffset);
      expect(totalFeatureCount, offset);
    });

    test('action part: base, claim and beatability features', () {
      final names = {
        for (final g in groups)
          g['name'] as String: (g['features'] as List).cast<String>(),
      };
      final action = names['action']!;
      // The base features end with the hand shape after the action.
      expect(action[actionClaimOffset - 1], 'after_low_singles');
      expect(action.sublist(actionClaimOffset, actionBeatOffset), [
        'after_claim_min_beatable',
        'after_claim_unbeatable',
        'after_claimable',
      ]);
      // Then the graded beatability features.
      expect(action.sublist(actionBeatOffset), [
        'beaters',
        'single_beat_share',
        'left_can_answer',
        'right_can_answer',
      ]);
    });
  });
}
