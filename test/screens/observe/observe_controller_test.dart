import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/record/game_record_store.dart';
import 'package:tichu/screens/observe/observe_controller.dart';

void main() {
  test('steps a four-bot round move by move and records it', () async {
    final store = InMemoryGameRecordStore();
    final controller = ObserveController(
      store: store,
      phaseDelay: Duration.zero,
    );
    addTearDown(controller.dispose);

    await controller.start();
    expect(controller.gameId, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(controller.step, ObserveStep.move);

    var steps = 0;
    while (controller.step == ObserveStep.move && steps < 1000) {
      final before = controller.record!.events.length;
      await controller.continueGame();
      steps++;
      // Each Continue applies exactly the one pending move.
      expect(controller.record!.events.length, greaterThan(before));
    }
    expect(controller.step, ObserveStep.roundOver);

    final record = controller.record!;
    final kinds = record.events.map((final e) => e.kind).toSet();
    expect(
      kinds,
      containsAll(<String>[
        'deal',
        'grandTichu',
        'schupf',
        'hands',
        'play',
        'trick',
        'out',
        'roundEnd',
      ]),
    );
    final seqs = [for (final e in record.events) e.seq];
    expect(seqs, List<int>.generate(seqs.length, (final i) => i + 1));

    final firstPlay = record.events.firstWhere((final e) => e.kind == 'play');
    expect(firstPlay.data['hand'], hasLength(14));
    expect(firstPlay.data['lead'], isTrue);

    await controller.flushRecord();
    final stored = await store.load(record.id);
    expect(stored, isNotNull);
    expect(stored!['format'], 2);
    expect((stored['log']! as List).length, 1);
    expect(stored['mode'], 'observe');

    // The next round starts on Continue.
    await controller.continueGame();
    expect(controller.snapshot!.scoreState.roundNumber, 2);
    expect(controller.step, ObserveStep.move);
  });
}
