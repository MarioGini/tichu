import 'package:supabase/supabase.dart';
import 'package:tichu/services/multiplayer/table_projection_store.dart';

class SupabaseTableProjectionStore implements GameTableProjectionStore {
  SupabaseTableProjectionStore({required this._client});

  static const String lobbyViewTable = 'tichu_lobby_views';
  static const String matchViewTable = 'tichu_match_player_views';
  static const String connectionViewTable = 'tichu_match_connection_views';

  final SupabaseClient _client;

  @override
  Future<void> replaceLobbyViews(
    String lobbyId,
    List<ProjectedLobbyView> views,
  ) async {
    await _replaceRows(
      table: lobbyViewTable,
      scopeColumn: 'lobby_id',
      scopeValue: lobbyId,
      keyColumn: 'access_token',
      keepKeys: views.map((view) => view.accessToken).toSet(),
      rows: [for (final view in views) _lobbyRow(view)],
      onConflict: 'lobby_id,access_token',
    );
  }

  @override
  Future<void> replaceMatchViews(
    String matchId,
    List<ProjectedMatchView> views,
  ) async {
    await _replaceRows(
      table: matchViewTable,
      scopeColumn: 'match_id',
      scopeValue: matchId,
      keyColumn: 'access_token',
      keepKeys: views.map((view) => view.accessToken).toSet(),
      rows: [for (final view in views) _matchRow(view)],
      onConflict: 'match_id,access_token',
    );
  }

  @override
  Future<void> replaceConnectionViews(
    String matchId,
    List<ProjectedConnectionView> views,
  ) async {
    await _replaceRows(
      table: connectionViewTable,
      scopeColumn: 'match_id',
      scopeValue: matchId,
      keyColumn: 'access_token',
      keepKeys: views.map((view) => view.accessToken).toSet(),
      rows: [for (final view in views) _connectionRow(view)],
      onConflict: 'match_id,access_token',
    );
  }

  @override
  Future<void> deleteLobbyState(String lobbyId, {String? matchId}) async {
    await _client.from(lobbyViewTable).delete().eq('lobby_id', lobbyId);
    if (matchId != null) {
      await _client.from(matchViewTable).delete().eq('match_id', matchId);
      await _client.from(connectionViewTable).delete().eq('match_id', matchId);
    }
  }

  Future<void> _replaceRows({
    required String table,
    required String scopeColumn,
    required String scopeValue,
    required String keyColumn,
    required Set<String> keepKeys,
    required List<Map<String, dynamic>> rows,
    required String onConflict,
  }) async {
    final existingRows = await _client
        .from(table)
        .select(keyColumn)
        .eq(scopeColumn, scopeValue);
    final existingKeys = <String>{
      for (final row in _decodeRows(existingRows))
        if (row[keyColumn] is String) row[keyColumn] as String,
    };

    final staleKeys = existingKeys.difference(keepKeys);
    for (final staleKey in staleKeys) {
      await _client
          .from(table)
          .delete()
          .eq(scopeColumn, scopeValue)
          .eq(keyColumn, staleKey);
    }

    if (rows.isEmpty) {
      return;
    }

    await _client.from(table).upsert(rows, onConflict: onConflict);
  }

  List<Map<String, dynamic>> _decodeRows(dynamic response) {
    if (response is List) {
      return response
          .whereType<Map<dynamic, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Map<String, dynamic> _lobbyRow(ProjectedLobbyView view) => {
    'lobby_id': view.lobbyId,
    'auth_user_id': view.authUserId,
    'access_token': view.accessToken,
    'player_id': view.playerId,
    'payload': view.payload,
  };

  Map<String, dynamic> _matchRow(ProjectedMatchView view) => {
    'lobby_id': view.lobbyId,
    'match_id': view.matchId,
    'auth_user_id': view.authUserId,
    'access_token': view.accessToken,
    'player_id': view.playerId,
    'revision': view.revision,
    'payload': view.payload,
  };

  Map<String, dynamic> _connectionRow(ProjectedConnectionView view) => {
    'lobby_id': view.lobbyId,
    'match_id': view.matchId,
    'auth_user_id': view.authUserId,
    'access_token': view.accessToken,
    'player_id': view.playerId,
    'payload': view.payload,
  };
}
