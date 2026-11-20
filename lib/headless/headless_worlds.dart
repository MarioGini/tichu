part of 'headless.dart';

/// Re-dealt worlds for multi-world rollout labels (`--rollout-worlds=K`).
///
/// A world keeps everything the deciding player knows: their own hand, the
/// cards played, every hand size, and the cards they passed in this round's
/// schupf that the receiver still holds. The other unseen cards are dealt
/// uniformly at random to the other players.
extension _Worlds on _HeadlessSimulator {
  GameEngineState _redeal(final GameEngineState state, final String actorId) {
    final world = state.copy();
    final actor = world.players.firstWhere((final p) => p.id == actorId);
    String idAt(final int offset) => world.players
        .firstWhere((final p) => p.seat == (actor.seat + offset) % 4)
        .id;
    final pass = world.completedSchupfSelections[actorId];
    final pinned = <String, List<Card>>{};
    if (pass != null) {
      for (final (offset, card) in [
        (1, pass.toLeft),
        (2, pass.toPartner),
        (3, pass.toRight),
      ]) {
        final id = idAt(offset);
        final hand = world.hands[id] ?? const <Card>[];
        final i = hand.indexWhere(
          (final c) => c.face == card.face && c.color == card.color,
        );
        if (i >= 0) (pinned[id] ??= []).add(hand[i]);
      }
    }
    final others = [
      for (final p in world.players)
        if (p.id != actorId && (world.hands[p.id]?.isNotEmpty ?? false)) p.id,
    ];
    final pool = <Card>[];
    for (final id in others) {
      final keep = pinned[id] ?? const <Card>[];
      for (final c in world.hands[id]!) {
        if (!keep.any((final k) => identical(k, c))) pool.add(c);
      }
    }
    pool.shuffle(random);
    var next = 0;
    for (final id in others) {
      final size = world.hands[id]!.length;
      final keep = pinned[id] ?? const <Card>[];
      final hand = [...keep];
      while (hand.length < size) {
        hand.add(pool[next++]);
      }
      world.hands[id] = hand;
    }
    return world;
  }

  /// Rollout values of every legal action in [rolloutWorlds] - 1 re-dealt
  /// worlds (the real deal is the caller's first world). Null entries: not
  /// rolled out (cap) or the world got stuck.
  Future<List<List<double?>>> _worldRollouts({
    required final GameEngine engine,
    required final GameEngineState state,
    required final GameAction chosen,
  }) async {
    final out = <List<double?>>[];
    for (var w = 1; w < rolloutWorlds; w++) {
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
