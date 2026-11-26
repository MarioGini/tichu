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
    required GameEngineState state,
    required GameSnapshot snapshot,
    required GameAction chosen,
  }) async {
    final playerId = chosen.playerId;
    final hand = List<Card>.from(snapshot.hands[playerId] ?? const <Card>[]);
    final (:legalTurns, :canPass) = _decisionActions(snapshot, playerId);
    final count = legalTurns.length + (canPass ? 1 : 0);
    if (count < 2) return null;
    // Going out is a hard rule of every bot, not a learned decision.
    if (legalTurns.any((t) => t.cards.length == hand.length)) {
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

    final team = state.players.firstWhere((p) => p.id == playerId).seat % 2;
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
      simulationEngine.applyAction(fork, action);
      final diff = await playOutRound(fork, forkAgents);
      if (diff != null) {
        values[i] = (team == 0 ? diff : -diff).toDouble();
        final score = fork.scoreTracker.state;
        own[i] = (team == 0 ? score.teamOneRound : score.teamTwoRound)
            .toDouble();
      }
    }
    return (diff: values, own: own);
  }

  String _slotKey(List<Card> cards) {
    final slots = [for (final c in cards) cardSlot(c)]..sort();
    return slots.join(',');
  }
}
