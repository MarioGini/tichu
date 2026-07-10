/// Persistence interface for authority-owned lobby and match state.
///
/// An in-memory authority uses the noop implementation. A production authority
/// backed by Postgres persists lobby metadata and the match action log so that
/// active lobbies survive process restarts and matches have an audit trail.
abstract interface class AuthorityStateStore {
  /// Saves or updates the serialized state of a lobby.
  Future<void> saveLobbyState(
    final String lobbyId,
    final Map<String, dynamic> state,
  );

  /// Loads all lobby states that were active at the last checkpoint.
  Future<Map<String, Map<String, dynamic>>> loadAllLobbyStates();

  /// Removes a lobby state entry.
  Future<void> deleteLobbyState(final String lobbyId);

  /// Appends a game action to the ordered action log for a match.
  Future<void> appendAction(
    final String matchId,
    final String lobbyId,
    final Map<String, dynamic> action,
  );

  /// Loads the ordered action log for a match.
  Future<List<Map<String, dynamic>>> loadActions(final String matchId);
}

class NoopAuthorityStateStore implements AuthorityStateStore {
  const NoopAuthorityStateStore();

  @override
  Future<void> saveLobbyState(
    final String lobbyId,
    final Map<String, dynamic> state,
  ) async {}

  @override
  Future<Map<String, Map<String, dynamic>>> loadAllLobbyStates() async =>
      const <String, Map<String, dynamic>>{};

  @override
  Future<void> deleteLobbyState(final String lobbyId) async {}

  @override
  Future<void> appendAction(
    final String matchId,
    final String lobbyId,
    final Map<String, dynamic> action,
  ) async {}

  @override
  Future<List<Map<String, dynamic>>> loadActions(final String matchId) async =>
      const <Map<String, dynamic>>[];
}
