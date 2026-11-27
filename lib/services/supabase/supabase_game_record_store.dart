import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tichu/game/record/game_record.dart';
import 'package:tichu/game/record/game_record_store.dart';
import 'package:tichu/services/supabase/supabase_app_client.dart';

/// Uploads game records from the app to `public.tichu_game_records`
/// (see `supabase/migrations/*_tichu_game_records.sql`), as the app's
/// anonymous user, and every round to `public.tichu_round_records` (one row
/// per round, looked up by its id). Rows are owned by that user (row-level
/// security).
class SupabaseGameRecordStore implements GameRecordStore {
  SupabaseGameRecordStore({Future<SupabaseClient> Function()? client})
    : _client = client ?? appSupabaseClient;

  static const table = 'tichu_game_records';
  static const roundTable = 'tichu_round_records';

  final Future<SupabaseClient> Function() _client;

  /// Error of the last upload, null once an upload succeeded.
  Object? lastError;
  DateTime? lastSavedAt;

  /// Round rows as last uploaded (by round id), so unchanged rounds are
  /// not sent again.
  final Map<String, String> _savedRounds = {};

  @override
  Future<void> save(GameRecord record) async {
    try {
      final client = await _client();
      await client.from(table).upsert({
        'id': record.id,
        'mode': record.mode,
        'complete': record.complete,
        'summary': record.summaryJson(),
        'record': record.toJson(),
        'created_at': record.createdAt.toIso8601String(),
        'updated_at': record.updatedAt.toIso8601String(),
      });
      final rounds = [
        for (final r in record.roundLogs)
          {
            'id': r.id,
            'game_id': record.id,
            'round': r.round,
            'log': r.encode(),
            'complete': r.complete,
            'team_one_points': r.teamOnePoints,
            'team_two_points': r.teamTwoPoints,
            'updated_at': record.updatedAt.toIso8601String(),
          },
      ];
      final changed = [
        for (final row in rounds)
          if (_savedRounds[row['id']! as String] != _signature(row)) row,
      ];
      if (changed.isNotEmpty) {
        await client
            .from(roundTable)
            .upsert(changed, onConflict: 'game_id,round');
        for (final row in changed) {
          _savedRounds[row['id']! as String] = _signature(row);
        }
      }
      lastError = null;
      lastSavedAt = DateTime.now();
    } on Object catch (error) {
      lastError = error;
      rethrow;
    }
  }

  @override
  Future<Map<String, Object?>?> load(String id) async {
    final client = await _client();
    final row = await client
        .from(table)
        .select('record')
        .eq('id', id)
        .maybeSingle();
    final record = row?['record'];
    return record == null ? null : Map<String, Object?>.from(record as Map);
  }

  static String _signature(Map<String, Object?> row) =>
      '${row['log']}|${row['team_one_points']}|${row['team_two_points']}';

  @override
  String describeLocation(String id) => "Supabase: $table where id = '$id'";
}
