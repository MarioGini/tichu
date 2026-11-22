part of 'headless.dart';

/// Exact counterfactual values of every legal play ("rollout labels").
///
/// For a play decision the round is forked once per legal action, the action
/// is applied and the round is played out with fresh, non-exploring agents.
/// The deal is fixed and the bots are deterministic, so the *differences*
/// between the returned values carry no card luck at all: they are the exact
/// effect of the action under the current policies. Regressing a Q-net on
/// them is one step of rollout policy iteration (the acting net still only
/// sees public information; averaged over deals it learns E[Q | info state]).
extension _Rollouts on _HeadlessSimulator {
  /// Values (round point difference for the actor's team) aligned with the
  /// bc-jsonl legal-action order: wish-filtered legal turns, then pass.
  /// `null` entries were not rolled out (action cap). Returns null when the
  /// decision is not worth labelling (forced move, finishing move available).
  /// `own` holds the actor's team's own round points for the same rollouts
  /// (with `diff` they give both teams' points, for match-win targets).
  Future<({List<double?> diff, List<double?> own})?> _rolloutValues({
    required final GameEngine engine,
    required final GameEngineState state,
    required final GameSnapshot snapshot,
    required final GameAction chosen,
  }) async {
    final playerId = chosen.playerId;
    final hand = List<Card>.from(snapshot.hands[playerId] ?? const <Card>[]);
    final (:legalTurns, :canPass) = _decisionActions(snapshot, playerId);
    final count = legalTurns.length + (canPass ? 1 : 0);
    if (count < 2) return null;
    // Going out is a hard rule of every bot, not a learned decision.
    if (legalTurns.any((final t) => t.cards.length == hand.length)) {
      return null;
    }

    final chosenKey = chosen is PlayTurnAction ? _slotKey(chosen.cards) : null;
    var chosenIndex = chosen is PassAction ? count - 1 : -1;
    for (var i = 0; i < legalTurns.length && chosenIndex < 0; i++) {
      if (_slotKey(legalTurns[i].cards) == chosenKey) chosenIndex = i;
    }

    var indices = [for (var i = 0; i < count; i++) i];
    if (count > rolloutMaxActions) {
      indices = ([...indices]..remove(chosenIndex))..shuffle(random);
      indices = [
        if (chosenIndex >= 0) chosenIndex,
        ...indices.take(rolloutMaxActions - (chosenIndex >= 0 ? 1 : 0)),
      ];
    }

    final team =
        state.players.firstWhere((final p) => p.id == playerId).seat % 2;
    final values = List<double?>.filled(count, null);
    final own = List<double?>.filled(count, null);
    for (final i in indices) {
      final fork = state.copy();
      final forkAgents = {
        for (final p in fork.players) p.id: agentFactory(p.id, p.seat),
      };
      final GameAction action;
      if (i >= legalTurns.length) {
        action = PassAction(playerId: playerId);
      } else {
        final actor = forkAgents[playerId];
        action = actor is SmartAiAgent
            ? actor.playActionFor(snapshot, legalTurns[i])
            : PlayTurnAction(
                playerId: playerId,
                cards: List<Card>.from(legalTurns[i].cards),
              );
      }
      try {
        engine.applyAction(fork, action);
        // Agents signal "no legal action" with StateError.
        // ignore: avoid_catching_errors
      } on StateError {
        continue;
      }
      final diff = await _playOutRound(engine, fork, forkAgents);
      if (diff != null) {
        values[i] = (team == 0 ? diff : -diff).toDouble();
        final score = fork.scoreTracker.state;
        own[i] = (team == 0 ? score.teamOneRound : score.teamTwoRound)
            .toDouble();
      }
    }
    return (diff: values, own: own);
  }

  /// Play [fork] to the end of the round; returns team one's round points
  /// minus team two's, or null when the playout got stuck.
  Future<int?> _playOutRound(
    final GameEngine engine,
    final GameEngineState fork,
    final Map<String, PlayerAgent> forkAgents,
  ) async {
    for (var steps = 0; steps < 5000; steps++) {
      final score = fork.scoreTracker.state;
      if (score.roundComplete) return score.teamOneRound - score.teamTwoRound;
      final request = AgentDecisions.next(engine, fork);
      if (request == null) return null;
      final snap = engine.buildSnapshot(fork);
      GameAction? action;
      try {
        action = await AgentDecisions.resolve(
          request,
          forkAgents[request.playerId]!,
          snap,
          fork,
        );
        // Agents signal "no legal action" with StateError.
        // ignore: avoid_catching_errors
      } on StateError {
        return null;
      }
      if (action == null) continue;
      engine.applyAction(fork, action);
    }
    return null;
  }

  String _slotKey(final List<Card> cards) {
    final slots = [for (final c in cards) cardSlot(c)]..sort();
    return slots.join(',');
  }
}
