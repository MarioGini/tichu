import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/record/game_record.dart';
import 'package:tichu/game/record/round_log.dart';
import 'package:tichu/services/records/file_game_record_store.dart';

void main() {
  test('saves and loads a record as <id>.json', () async {
    final dir = await Directory.systemTemp.createTemp('tichu_records');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileGameRecordStore(dir);
    final record = GameRecord(
      id: generateUuidV4(),
      players: const [
        GamePlayer(id: 'a', name: 'A', seat: 0, type: PlayerType.human),
      ],
      targetScore: 1000,
    );
    record.roundLogs.add(RoundLog(round: 1)..actions.add('0-'));

    await store.save(record);

    expect(File('${dir.path}/${record.id}.json').existsSync(), isTrue);
    final loaded = await store.load(record.id);
    expect(loaded!['id'], record.id);
    expect(loaded['mode'], 'play');
    expect(loaded['format'], 2);
    expect((loaded['log']! as List).single, containsPair('m', '0-'));
    expect(await store.load('missing'), isNull);
  });

  test('generateUuidV4 produces version-4 UUIDs', () {
    final ids = {for (var i = 0; i < 100; i++) generateUuidV4()};
    expect(ids, hasLength(100));
    for (final id in ids) {
      expect(
        id,
        matches(
          RegExp(
            '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
            r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    }
  });
}
