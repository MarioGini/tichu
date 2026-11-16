// Prints a stored game record as a readable, numbered timeline.
//
//   dart run tool/game_record.dart <game-id | path/to/record.json>
//       [--round N] [--from SEQ] [--to SEQ] [--hands]
//
// A bare game id is looked up in the default record directory
// (see FileGameRecordStore.defaultLocation).
import 'dart:convert';
import 'dart:io';

import 'package:tichu/services/records/file_game_record_store.dart';

Future<void> main(final List<String> args) async {
  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    stdout.writeln(
      'Usage: dart run tool/game_record.dart <game-id | file.json> '
      '[--round N] [--from SEQ] [--to SEQ] [--hands]',
    );
    return;
  }
  int? intArg(final String flag) {
    final i = args.indexOf(flag);
    return i >= 0 && i + 1 < args.length ? int.parse(args[i + 1]) : null;
  }

  final target = args.first;
  final Map<String, Object?> record;
  if (File(target).existsSync()) {
    record = Map<String, Object?>.from(
      jsonDecode(File(target).readAsStringSync()) as Map,
    );
  } else {
    final store = FileGameRecordStore.defaultLocation();
    final loaded = await store.load(target);
    if (loaded == null) {
      stderr.writeln('No record at ${store.describeLocation(target)}');
      exitCode = 1;
      return;
    }
    record = loaded;
  }

  final round = intArg('--round');
  final from = intArg('--from') ?? 0;
  final to = intArg('--to') ?? 1 << 30;
  final showHands = args.contains('--hands');
  final names = {
    for (final p in (record['players']! as List).cast<Map<String, Object?>>())
      p['id']! as String: p['name']! as String,
  };

  stdout.writeln(
    'Game ${record['id']} (${record['mode']}), bots: ${record['bots']}, '
    'score ${record['teamOneTotal']}:${record['teamTwoTotal']}'
    '${record['complete'] == true ? ' (complete)' : ''}',
  );
  for (final e in (record['events']! as List).cast<Map<String, Object?>>()) {
    final seq = e['seq']! as int;
    if (round != null && e['round'] != round) continue;
    if (seq < from || seq > to) continue;
    stdout.writeln('#$seq r${e['round']} ${e['text']}');
    if (!showHands) continue;
    final hand = e['hand'];
    if (hand is List) stdout.writeln('      hand: ${hand.join(' ')}');
    final hands = e['hands'];
    if (hands is Map) {
      for (final h in hands.entries) {
        stdout.writeln(
          '      ${names[h.key] ?? h.key}: ${(h.value as List).join(' ')}',
        );
      }
    }
  }
}
