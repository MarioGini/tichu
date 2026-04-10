import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:tichu/services/multiplayer/authority_state_store.dart';

/// Postgres-backed [AuthorityStateStore] that persists lobby metadata and match
/// action logs so the authority can recover active lobbies after a restart.
class PostgresAuthorityStateStore implements AuthorityStateStore {
  PostgresAuthorityStateStore({required final String databaseUrl})
    : _databaseUrl = databaseUrl;

  final String _databaseUrl;

  @override
  Future<void> saveLobbyState(
    final String lobbyId,
    final Map<String, dynamic> state,
  ) async {
    final connection = await Connection.openFromUrl(_databaseUrl);
    try {
      await connection.execute(
        Sql.named('''
insert into public.tichu_authority_lobbies (lobby_id, state, updated_at)
values (@lobbyId, @state, timezone('utc', now()))
on conflict (lobby_id) do update
set state = excluded.state, updated_at = excluded.updated_at
'''),
        parameters: <String, Object?>{
          'lobbyId': lobbyId,
          'state': jsonEncode(state),
        },
      );
    } finally {
      await connection.close();
    }
  }

  @override
  Future<Map<String, Map<String, dynamic>>> loadAllLobbyStates() async {
    final connection = await Connection.openFromUrl(_databaseUrl);
    try {
      final result = await connection.execute(
        'select lobby_id, state from public.tichu_authority_lobbies',
      );
      final lobbies = <String, Map<String, dynamic>>{};
      for (final row in result) {
        final lobbyId = row[0] as String;
        final stateRaw = row[1];
        final state = stateRaw is String
            ? Map<String, dynamic>.from(jsonDecode(stateRaw) as Map)
            : Map<String, dynamic>.from(stateRaw as Map);
        lobbies[lobbyId] = state;
      }
      return lobbies;
    } finally {
      await connection.close();
    }
  }

  @override
  Future<void> deleteLobbyState(final String lobbyId) async {
    final connection = await Connection.openFromUrl(_databaseUrl);
    try {
      await connection.execute(
        Sql.named(
          'delete from public.tichu_authority_lobbies where lobby_id = @lobbyId',
        ),
        parameters: <String, Object?>{'lobbyId': lobbyId},
      );
    } finally {
      await connection.close();
    }
  }

  @override
  Future<void> appendAction(
    final String matchId,
    final String lobbyId,
    final Map<String, dynamic> action,
  ) async {
    final connection = await Connection.openFromUrl(_databaseUrl);
    try {
      await connection.execute(
        Sql.named('''
insert into public.tichu_authority_actions
    (match_id, lobby_id, seq, action, created_at)
values (
    @matchId, @lobbyId,
    coalesce(
        (select max(seq) + 1 from public.tichu_authority_actions
         where match_id = @matchId), 1),
    @action,
    timezone('utc', now())
)
'''),
        parameters: <String, Object?>{
          'matchId': matchId,
          'lobbyId': lobbyId,
          'action': jsonEncode(action),
        },
      );
    } finally {
      await connection.close();
    }
  }

  @override
  Future<List<Map<String, dynamic>>> loadActions(final String matchId) async {
    final connection = await Connection.openFromUrl(_databaseUrl);
    try {
      final result = await connection.execute(
        Sql.named(
          'select action from public.tichu_authority_actions '
          'where match_id = @matchId order by seq asc',
        ),
        parameters: <String, Object?>{'matchId': matchId},
      );
      return <Map<String, dynamic>>[
        for (final row in result)
          Map<String, dynamic>.from(
            (row[0] is String ? jsonDecode(row[0] as String) : row[0]) as Map,
          ),
      ];
    } finally {
      await connection.close();
    }
  }
}
