import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('policy builder converts transitions into averaged returns', () async {
    final tempDir = await Directory.systemTemp.createTemp('tichu_rl_builder_');
    final transitionsFile = File('${tempDir.path}/transitions.jsonl');
    final policyFile = File('${tempDir.path}/policy.json');

    try {
      final lines = [
        jsonEncode({
          'episode': 1,
          'seq': 1,
          'team': 0,
          'state_key': 's1',
          'state_key_coarse': 'c1',
          'action_key': 'a1',
          'policy_action_key': 'p1',
          'action_type': 'play',
          'reward': 1,
          'discount': 1,
          'done': false,
        }),
        jsonEncode({
          'episode': 1,
          'seq': 2,
          'team': 1,
          'state_key': 's2',
          'state_key_coarse': 'c2',
          'action_key': 'a2',
          'action_type': 'schupf',
          'reward': 2,
          'discount': 1,
          'done': false,
        }),
        jsonEncode({
          'episode': 1,
          'seq': 3,
          'team': 0,
          'state_key': 's3',
          'state_key_coarse': 'c1',
          'action_key': 'a3',
          'policy_action_key': 'p3',
          'action_type': 'play',
          'reward': 3,
          'discount': 0,
          'done': true,
        }),
      ];
      await transitionsFile.writeAsString('${lines.join('\n')}\n');

      final processResult = await Process.run('dart', [
        'run',
        'tool/rl/build_policy_from_transitions.dart',
        '--input=${transitionsFile.path}',
        '--output=${policyFile.path}',
        '--gamma=0.5',
      ], workingDirectory: Directory.current.path);

      expect(
        processResult.exitCode,
        0,
        reason: processResult.stderr.toString(),
      );
      expect(policyFile.existsSync(), isTrue);

      final decoded =
          jsonDecode(await policyFile.readAsString()) as Map<String, dynamic>;

      final builder = decoded['builder'] as Map<String, dynamic>;
      expect(builder['algorithm'], 'monte_carlo_conservative_advantage');
      expect(builder['gamma'], 0.5);
      expect(builder['episodes_seen'], 1);
      expect(builder['transitions_seen'], 3);
      expect(builder['transitions_used'], 2);

      final stateActionValues =
          decoded['state_action_values'] as Map<String, dynamic>;
      expect(stateActionValues, isEmpty);

      final coarseStateActionValues =
          decoded['coarse_state_action_values'] as Map<String, dynamic>;
      final c1 = coarseStateActionValues['c1'] as Map<String, dynamic>;

      expect(c1, isNot(contains('p1')));
      expect((c1['p3'] as num).toDouble(), closeTo(1.125, 1e-9));
      expect(coarseStateActionValues, isNot(contains('c2')));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
