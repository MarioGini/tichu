import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/heuristic_options.dart';

void main() {
  test('parses presets and rule lists', () {
    expect(HeuristicOptions.parse('latest').guardPartnerTichu, isTrue);
    expect(HeuristicOptions.parse('latest').strictTichu, isTrue);
    final legacy = HeuristicOptions.parse('legacy');
    expect(legacy.guardPartnerTichu, isFalse);
    expect(legacy.supportPartnerTichu, isFalse);
    expect(legacy.strictTichu, isFalse);
    expect(legacy.announceBeforeSchupf, isFalse);
    final custom = HeuristicOptions.parse('support,announce');
    expect(custom.supportPartnerTichu, isTrue);
    expect(custom.announceBeforeSchupf, isTrue);
    expect(custom.guardPartnerTichu, isFalse);
    expect(custom.strictTichu, isFalse);
  });

  test('rejects unknown rules', () {
    expect(() => HeuristicOptions.parse('support,bogus'), throwsArgumentError);
  });
}
