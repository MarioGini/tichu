part of 'headless.dart';

/// Exact counterfactual values of schupf candidates (`--schupf-rollout-rate`).
///
/// For a sampled schupf decision the round is forked once per candidate
/// pass (the heuristic's choice first, then sensible alternatives: a strong
/// card to the partner, low cards to the opponents within the bomb-safety
/// parity convention) and played out to the end of the round by the current
/// bots. Same deal, deterministic bots: the differences between candidates
/// are the exact effect of the pass. Besides the round score, each outcome
/// records double wins and the Tichu calls that followed, so the effect of
/// a pass on the partner's and the opponents' play can be analysed.
extension _SchupfLabels on _HeadlessSimulator {
  bool _sameCard(Card a, Card b) => a.face == b.face && a.color == b.color;

  /// The bot's own pass first, then up to [schupfCandidates] - 1 random
  /// others from [SchupfFeatures.candidates].
  List<SchupfAction> _schupfCandidates(
    String playerId,
    List<Card> hand,
    SchupfAction chosen,
  ) {
    bool isChosen(int l, int p, int r) =>
        _sameCard(hand[l], chosen.toLeft) &&
        _sameCard(hand[p], chosen.toPartner) &&
        _sameCard(hand[r], chosen.toRight);
    final all = [
      for (final (l, p, r) in SchupfFeatures.candidates(
        hand,
        extended: schupfExtended,
      ))
        if (!isChosen(l, p, r))
          SchupfAction(
            playerId: playerId,
            toLeft: hand[l],
            toPartner: hand[p],
            toRight: hand[r],
          ),
    ]..shuffle(random);
    if (!schupfLabelAll) return [chosen, ...all.take(schupfCandidates - 1)];
    // Half the alternatives from every pass: the sensible set only guides
    // the sampling, it does not limit what the net can learn.
    final any = [
      for (final (l, p, r) in SchupfFeatures.allPasses(hand.length))
        if (!isChosen(l, p, r))
          SchupfAction(
            playerId: playerId,
            toLeft: hand[l],
            toPartner: hand[p],
            toRight: hand[r],
          ),
    ]..shuffle(random);
    // A third each: the sensible set, neighbours of the bot's own pass (one
    // card replaced or two slots swapped: each label then prices a single
    // choice, e.g. keeping the Dog), and any pass at all.
    final own = [
      for (final c in [chosen.toLeft, chosen.toPartner, chosen.toRight])
        hand.indexWhere((h) => _sameCard(h, c)),
    ];
    final near = <SchupfAction>[];
    void addNear(int l, int p, int r) => near.add(
      SchupfAction(
        playerId: playerId,
        toLeft: hand[l],
        toPartner: hand[p],
        toRight: hand[r],
      ),
    );
    for (var i = 0; i < hand.length; i++) {
      if (own.contains(i)) continue;
      addNear(i, own[1], own[2]);
      addNear(own[0], i, own[2]);
      addNear(own[0], own[1], i);
    }
    addNear(own[1], own[0], own[2]);
    addNear(own[0], own[2], own[1]);
    addNear(own[2], own[1], own[0]);
    near.shuffle(random);
    bool allowed(SchupfAction a) =>
        SchupfRules.allows(a.toLeft, a.toPartner, a.toRight);
    near.retainWhere(allowed);
    any.retainWhere(allowed);
    final third = (schupfCandidates - 1) ~/ 3;
    return [
      chosen,
      ...all.take(third),
      ...near.take(third),
      ...any.take(schupfCandidates - 1 - 2 * third),
    ];
  }

  /// Outcome per candidate: [round diff for my team, my team went out
  /// first (1/0), double win (1 mine / -1 theirs / 0), my call, partner's
  /// call, best opponent call]. Call codes: 0 none, 1 Tichu lost, 2 Tichu
  /// made, 3 Grand Tichu lost, 4 Grand Tichu made.
  Future<void> _labelSchupf({
    required GameEngineState state,
    required GameSnapshot snapshot,
    required String playerId,
    required SchupfAction chosen,
  }) async {
    final hand = List<Card>.from(snapshot.hands[playerId] ?? const <Card>[]);
    if (hand.length < 3) return;
    final candidates = _schupfCandidates(playerId, hand, chosen);
    final me = state.players.firstWhere((p) => p.id == playerId);
    final team = me.seat % 2;
    final partnerId = state.players
        .firstWhere((p) => p.seat == (me.seat + 2) % 4)
        .id;
    final outcomes = <List<int>?>[];
    for (final candidate in candidates) {
      final fork = state.copy();
      final agents = {
        for (final p in fork.players) p.id: agentFactory(p.id, p.seat),
      };
      simulationEngine.applyAction(fork, candidate);
      final diff = await playOutRound(fork, agents);
      if (diff == null) {
        outcomes.add(null);
        continue;
      }
      final score = fork.scoreTracker.state;
      final order = score.finishOrder;
      int teamOf(String id) =>
          fork.players.firstWhere((p) => p.id == id).seat % 2;
      final firstMine = order.isNotEmpty && teamOf(order.first) == team;
      final doubleWin =
          order.length >= 2 && teamOf(order[0]) == teamOf(order[1]);
      int callCode(String id) {
        final call = score.tichuCalls[id] ?? TichuCall.none;
        if (call == TichuCall.none) return 0;
        final made = order.isNotEmpty && order.first == id;
        return (call == TichuCall.grandTichu ? 3 : 1) + (made ? 1 : 0);
      }

      var opp = 0;
      for (final p in fork.players) {
        if (p.seat % 2 != team) opp = max(opp, callCode(p.id));
      }
      final first = firstMine ? 1 : 0;
      final dbl = !doubleWin ? 0 : (firstMine ? 1 : -1);
      outcomes.add([
        if (team == 0) diff else -diff,
        first,
        dbl,
        callCode(playerId),
        callCode(partnerId),
        opp,
      ]);
    }
    _bcWriter?.emitSchupfLabels(
      snapshot: snapshot,
      playerId: playerId,
      candidates: candidates,
      outcomes: outcomes,
    );
  }
}
