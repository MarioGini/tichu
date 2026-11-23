part of 'headless.dart';

/// Exact labels for the two small heuristic decisions (`--side-rollout-rate`):
/// who gets a trick won with the Dragon, and the Mah Jong wish. Every option
/// is applied to a copy of the state and the round is played out with fresh,
/// non-exploring bots, as for play labels.
///
/// Rows: `{"side": "dragon"|"wish", "options": [...], "values": [...],
/// "chosen": i, "state_features": [...], ...}`; values are the round point
/// difference for the decider's team (null = playout stuck).
extension _SideLabels on _HeadlessSimulator {
  Future<void> _labelSideDecision({
    required final GameEngine engine,
    required final GameEngineState state,
    required final GameSnapshot snapshot,
    required final GameAction action,
  }) async {
    final writer = _bcWriter;
    if (writer == null || sideRolloutRate <= 0) return;
    final isDragon = action is GiveDragonAction;
    final isWish =
        action is PlayTurnAction &&
        action.cards.any((final c) => c.face == CardFace.mahJong);
    if (!isDragon && !isWish) return;
    if (random.nextDouble() >= sideRolloutRate) return;

    final playerId = action.playerId;
    final team =
        state.players.firstWhere((final p) => p.id == playerId).seat % 2;
    final List<GameAction> options;
    final List<Object> optionLabels;
    if (isDragon) {
      final targets = engine.opponentIds(state, playerId);
      options = [
        for (final t in targets)
          GiveDragonAction(playerId: playerId, targetPlayerId: t),
      ];
      optionLabels = [
        for (final t in targets)
          state.players.firstWhere((final p) => p.id == t).seat,
      ];
    } else {
      final play = action as PlayTurnAction;
      final wishes = [CardFace.none, ...CardFace.values.where(isWishableFace)];
      options = [
        for (final w in wishes)
          PlayTurnAction(
            playerId: playerId,
            cards: List<Card>.from(play.cards),
            inputWish: w,
          ),
      ];
      optionLabels = [for (final w in wishes) w.name];
    }
    final values = <double?>[];
    for (final option in options) {
      final fork = state.copy();
      final forkAgents = {
        for (final p in fork.players) p.id: agentFactory(p.id, p.seat),
      };
      try {
        engine.applyAction(fork, option);
        // Agents signal "no legal action" with StateError.
        // ignore: avoid_catching_errors
      } on StateError {
        values.add(null);
        continue;
      }
      final diff = await _playOutRound(engine, fork, forkAgents);
      values.add(diff == null ? null : (team == 0 ? diff : -diff).toDouble());
    }
    final chosen = isDragon
        ? optionLabels.indexOf(
            state.players
                .firstWhere((final p) => p.id == action.targetPlayerId)
                .seat,
          )
        : optionLabels.indexOf((action as PlayTurnAction).inputWish.name);
    writer.emitSideDecision(
      kind: isDragon ? 'dragon' : 'wish',
      snapshot: snapshot,
      playerId: playerId,
      options: optionLabels,
      values: values,
      chosen: chosen,
      trickPoints: isDragon ? pointsForCards(state.pendingDragonTrickCards) : 0,
    );
  }
}
