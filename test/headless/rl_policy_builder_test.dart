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
          'schema_version': 'tichu_rl_transition_v2',
          'episode': 1,
          'seq': 1,
          'state_key': 's1',
          'action_key': 'a1',
          'reward': 1,
          'discount': 1,
          'done': false,
        }),
        jsonEncode({
          'schema_version': 'tichu_rl_transition_v2',
          'episode': 1,
          'seq': 2,
          'state_key': 's2',
          'action_key': 'a2',
          'reward': 2,
          'discount': 1,
          'done': false,
        }),
        jsonEncode({
          'schema_version': 'tichu_rl_transition_v2',
          'episode': 1,
          'seq': 3,
          'state_key': 's3',
          'action_key': 'a3',
          'reward': 3,
          'discount': 0,
          'done': true,
        }),
      ];
      await transitionsFile.writeAsString('${lines.join('\n')}\n');

      final processResult = await Process.run(Platform.resolvedExecutable, [
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
      expect(decoded['schema_version'], 'tichu_rl_policy_v1');
      expect(decoded['source_transition_schema'], 'tichu_rl_transition_v2');

      final builder = decoded['builder'] as Map<String, dynamic>;
      expect(builder['algorithm'], 'monte_carlo_state_action_returns');
      expect(builder['gamma'], 0.5);
      expect(builder['episodes_seen'], 1);
      expect(builder['transitions_used'], 3);

      final stateActionValues =
          decoded['state_action_values'] as Map<String, dynamic>;

      final s1 = stateActionValues['s1'] as Map<String, dynamic>;
      final s2 = stateActionValues['s2'] as Map<String, dynamic>;
      final s3 = stateActionValues['s3'] as Map<String, dynamic>;

      expect((s1['a1'] as num).toDouble(), closeTo(2.75, 1e-9));
      expect((s2['a2'] as num).toDouble(), closeTo(3.5, 1e-9));
      expect((s3['a3'] as num).toDouble(), closeTo(3.0, 1e-9));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
