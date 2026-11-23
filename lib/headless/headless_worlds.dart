part of 'headless.dart';

/// Re-dealt worlds for multi-world rollout labels (`--rollout-worlds=K`).
///
/// A world keeps everything the deciding player knows: their own hand, the
/// cards played, every hand size, and the cards they passed in this round's
/// schupf that the receiver still holds. The other unseen cards are dealt
/// uniformly at random to the other players.
extension _Worlds on _HeadlessSimulator {
  /// The labelling worlds keep the pre-search re-deal (pool in hand
  /// order), so labels stay reproducible with earlier runs.
  GameEngineState _redeal(final GameEngineState state, final String actorId) =>
      redealWorld(state, actorId, random, canonicalPool: false);

  /// Rollout values of every legal action in [rolloutWorlds] - 1 re-dealt
  /// worlds (the real deal is the caller's first world). Null entries: not
  /// rolled out (cap) or the world got stuck.
  Future<List<List<double?>>> _worldRollouts({
    required final GameEngine engine,
    required final GameEngineState state,
    required final GameAction chosen,
    final int? count,
  }) async {
    final out = <List<double?>>[];
    for (var w = 1; w < (count ?? rolloutWorlds); w++) {
      final world = _redeal(state, chosen.playerId);
      final values = await _rolloutValues(
        engine: engine,
        state: world,
        snapshot: engine.buildSnapshot(world),
        chosen: chosen,
      );
      if (values != null) out.add(values.diff);
    }
    return out;
  }
}
