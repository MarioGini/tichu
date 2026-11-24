// Prints a stored game record as a readable, numbered timeline.
//
//   dart run tool/game_record.dart <game-id | path/to/record.json>
//       [--round N] [--from SEQ] [--to SEQ] [--hands]
//
// A bare game id is fetched from Supabase when SUPABASE_URL is set
// (key from SUPABASE_SERVICE_ROLE_KEY, sent as the `apikey` header),
// otherwise looked up in the default record directory
// (see FileGameRecordStore.defaultLocation).
//
//   dart run tool/game_record.dart --latest   # newest games in Supabase
import 'dart:convert';
import 'dart:io';

import 'package:tichu/game/record/round_log.dart';
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

  final supabaseUrl = Platform.environment['SUPABASE_URL'] ?? '';
  if (args.first == '--latest') {
    final rows = await _supabaseGet(
      supabaseUrl,
      'select=id,summary&order=updated_at.desc&limit=15',
    );
    for (final row in rows) {
      stdout.writeln('${row['id']}  ${jsonEncode(row['summary'])}');
    }
    return;
  }

  final target = args.first;
  final Map<String, Object?> record;
  if (File(target).existsSync()) {
    record = Map<String, Object?>.from(
      jsonDecode(File(target).readAsStringSync()) as Map,
    );
  } else if (supabaseUrl.isNotEmpty) {
    final rows = await _supabaseGet(
      supabaseUrl,
      'select=record&id=eq.${Uri.encodeQueryComponent(target)}',
    );
    if (rows.isEmpty) {
      stderr.writeln('No record $target in Supabase');
      exitCode = 1;
      return;
    }
    record = Map<String, Object?>.from(rows.single['record']! as Map);
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
  if (record['log'] case final List<Object?> log) {
    // Format 3: one string per round (initial cards + move order), replayed.
    final players = (record['players']! as List).cast<Map<String, Object?>>();
    final seatNames = [
      for (var seat = 0; seat < 4; seat++)
        players.firstWhere((final p) => p['seat'] == seat)['name']! as String,
    ];
    var seq = 0;
    for (var i = 0; i < log.length; i++) {
      final n = i + 1;
      final steps = replayRoundLog(log[i]! as String, seatNames);
      final show = round == null || round == n;
      if (show) {
        stdout.writeln('── Round $n');
        if (showHands) {
          final hands = dealtHands(log[i]! as String);
          for (var seat = 0; seat < 4; seat++) {
            stdout.writeln(
              '      ${seatNames[seat]}: '
              '${hands[seat].map(cardIndexLabel).join(' ')}',
            );
          }
        }
      }
      for (final step in steps) {
        seq++;
        if (!show || seq < from || seq > to) continue;
        stdout.writeln('#$seq r$n ${step.text}');
        if (showHands) {
          stdout.writeln(
            '      hand: '
            '${step.hands[step.seat].map(cardIndexLabel).join(' ')}',
          );
        }
      }
    }
    return;
  }

  // Format 1: the full event list.
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

/// GET on the `tichu_game_records` REST endpoint of the Supabase project.
Future<List<Map<String, Object?>>> _supabaseGet(
  final String supabaseUrl,
  final String query,
) async {
  if (supabaseUrl.isEmpty) throw StateError('SUPABASE_URL is not set.');
  // A network proxy may inject the real key; any placeholder works then.
  final key =
      Platform.environment['SUPABASE_SERVICE_ROLE_KEY'] ?? 'injected-by-proxy';
  final client = HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;
  try {
    final base = supabaseUrl.endsWith('/') ? supabaseUrl : '$supabaseUrl/';
    final request = await client.getUrl(
      Uri.parse('${base}rest/v1/tichu_game_records?$query'),
    );
    request.headers.set('apikey', key);
    if (Platform.environment.containsKey('SUPABASE_SERVICE_ROLE_KEY')) {
      request.headers.set('Authorization', 'Bearer $key');
    }
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw StateError('Supabase answered ${response.statusCode}: $body');
    }
    return (jsonDecode(body) as List).cast<Map<String, Object?>>();
  } finally {
    client.close();
  }
}
