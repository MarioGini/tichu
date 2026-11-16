import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:tichu/game/record/game_record.dart';
import 'package:tichu/game/record/game_record_store.dart';

/// Stores game records in `public.tichu_game_records` (one row per game,
/// the whole record as jsonb). Used by the Supabase authority.
class PostgresGameRecordStore implements GameRecordStore {
  PostgresGameRecordStore({required final String databaseUrl})
    : _databaseUrl = databaseUrl;

  final String _databaseUrl;
  bool _tableReady = false;

  static const _createTable = '''
create table if not exists public.tichu_game_records (
    id text primary key,
    mode text not null,
    complete boolean not null default false,
    summary jsonb not null,
    record jsonb not null,
    created_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now())
)
''';

  Future<T> _withConnection<T>(
    final Future<T> Function(Connection connection) body,
  ) async {
    final connection = await Connection.openFromUrl(_databaseUrl);
    try {
      if (!_tableReady) {
        await connection.execute(_createTable);
        _tableReady = true;
      }
      return await body(connection);
    } finally {
      await connection.close();
    }
  }

  @override
  Future<void> save(final GameRecord record) => _withConnection(
    (final connection) => connection.execute(
      Sql.named('''
insert into public.tichu_game_records
    (id, mode, complete, summary, record, created_at, updated_at)
values (@id, @mode, @complete, @summary, @record, @createdAt,
        timezone('utc', now()))
on conflict (id) do update
set complete = excluded.complete, summary = excluded.summary,
    record = excluded.record, updated_at = excluded.updated_at
'''),
      parameters: <String, Object?>{
        'id': record.id,
        'mode': record.mode,
        'complete': record.complete,
        'summary': jsonEncode(record.summaryJson()),
        'record': jsonEncode(record.toJson()),
        'createdAt': record.createdAt,
      },
    ),
  );

  @override
  Future<Map<String, Object?>?> load(final String id) => _withConnection((
    final connection,
  ) async {
    final result = await connection.execute(
      Sql.named('select record from public.tichu_game_records where id = @id'),
      parameters: <String, Object?>{'id': id},
    );
    if (result.isEmpty) return null;
    final raw = result.first[0];
    return Map<String, Object?>.from(
      (raw is String ? jsonDecode(raw) : raw)! as Map,
    );
  });

  @override
  String describeLocation(final String id) =>
      "public.tichu_game_records where id = '$id'";
}
