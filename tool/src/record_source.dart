// Loads stored game records for the tools in tool/.
import 'dart:convert';
import 'dart:io';

import 'package:tichu/services/records/file_game_record_store.dart';

String get _supabaseUrl => Platform.environment['SUPABASE_URL'] ?? '';

/// A loaded game record and, when looked up by a round id, that round.
typedef LoadedRecord = ({Map<String, Object?> record, int? round});

/// The record [target] names: a record file, a game id or a round id
/// (`tichu_round_records`, the first 8 characters are enough) in Supabase
/// when SUPABASE_URL is set (key from SUPABASE_SERVICE_ROLE_KEY, sent as
/// the `apikey` header), otherwise a game id in the default record
/// directory (see FileGameRecordStore.defaultLocation). Null when there is
/// none; the reason is printed to stderr.
Future<LoadedRecord?> loadRecord(String target) async {
  final Map<String, Object?> record;
  int? roundFromId;
  if (File(target).existsSync()) {
    record = Map<String, Object?>.from(
      jsonDecode(File(target).readAsStringSync()) as Map,
    );
  } else if (_supabaseUrl.isNotEmpty) {
    var rows = await supabaseGet(
      'select=record&id=eq.${Uri.encodeQueryComponent(target)}',
    );
    if (rows.isEmpty && target.length >= 8) {
      // A round id (or its first characters).
      final rounds = [
        for (final r in await supabaseGet(
          'select=id,game_id,round'
          '&short_id=eq.${Uri.encodeQueryComponent(target.substring(0, 8))}',
          table: 'tichu_round_records',
        ))
          if ((r['id']! as String).startsWith(target.toLowerCase())) r,
      ];
      if (rounds.length > 1) {
        stderr.writeln('Round id $target is ambiguous; give more characters');
        return null;
      }
      if (rounds.length == 1) {
        final gameId = rounds.single['game_id']! as String;
        roundFromId = rounds.single['round']! as int;
        stdout.writeln(
          'Round ${rounds.single['id']}: game $gameId, '
          'round $roundFromId',
        );
        rows = await supabaseGet(
          'select=record&id=eq.${Uri.encodeQueryComponent(gameId)}',
        );
      }
    }
    if (rows.isEmpty) {
      stderr.writeln('No game or round $target in Supabase');
      return null;
    }
    record = Map<String, Object?>.from(rows.single['record']! as Map);
  } else {
    final store = FileGameRecordStore.defaultLocation();
    final loaded = await store.load(target);
    if (loaded == null) {
      stderr.writeln('No record at ${store.describeLocation(target)}');
      return null;
    }
    record = loaded;
  }
  return (record: record, round: roundFromId);
}

/// GET on the `tichu_game_records` REST endpoint of the Supabase project.
Future<List<Map<String, Object?>>> supabaseGet(
  String query, {
  String table = 'tichu_game_records',
}) async {
  final supabaseUrl = _supabaseUrl;
  if (supabaseUrl.isEmpty) throw StateError('SUPABASE_URL is not set.');
  // A network proxy may inject the real key; any placeholder works then.
  final key =
      Platform.environment['SUPABASE_SERVICE_ROLE_KEY'] ?? 'injected-by-proxy';
  final client = HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;
  try {
    final base = supabaseUrl.endsWith('/') ? supabaseUrl : '$supabaseUrl/';
    final request = await client.getUrl(
      Uri.parse('${base}rest/v1/$table?$query'),
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
