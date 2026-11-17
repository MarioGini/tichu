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
  static int _strength(final Card c) => switch (c.face) {
    CardFace.dog => 0,
    CardFace.mahJong => 1,
    CardFace.phoenix => 15,
    CardFace.dragon => 16,
    _ => faceRank(c.face),
  };

  bool _sameCard(final Card a, final Card b) =>
      a.face == b.face && a.color == b.color;

  List<SchupfAction> _schupfCandidates(
    final String playerId,
    final List<Card> hand,
    final SchupfAction chosen,
  ) {
    final sorted = [...hand]
      ..sort((final a, final b) => _strength(a).compareTo(_strength(b)));
    final partnerOpts = <Card>[
      ...sorted.reversed.take(5),
      ...sorted.where((final c) => c.face == CardFace.dog),
    ];
    final leftOpts = sorted.where(SchupfFeatures.allowedLeft).take(5).toList();
    final rightOpts = sorted
        .where(SchupfFeatures.allowedRight)
        .take(5)
        .toList();
    final all = <SchupfAction>[];
    for (final p in partnerOpts) {
      for (final l in leftOpts) {
        if (_sameCard(l, p)) continue;
        for (final r in rightOpts) {
          if (_sameCard(r, p) || _sameCard(r, l)) continue;
          all.add(
            SchupfAction(
              playerId: playerId,
              toLeft: l,
              toPartner: p,
              toRight: r,
            ),
          );
        }
      }
    }
    bool same(final SchupfAction a, final SchupfAction b) =>
        _sameCard(a.toLeft, b.toLeft) &&
        _sameCard(a.toPartner, b.toPartner) &&
        _sameCard(a.toRight, b.toRight);
    all
      ..removeWhere((final a) => same(a, chosen))
      ..shuffle(random);
    return [chosen, ...all.take(schupfCandidates - 1)];
  }

  /// Outcome per candidate: [round diff for my team, my team went out
  /// first (1/0), double win (1 mine / -1 theirs / 0), my call, partner's
  /// call, best opponent call]. Call codes: 0 none, 1 Tichu lost, 2 Tichu
  /// made, 3 Grand Tichu lost, 4 Grand Tichu made.
  Future<void> _labelSchupf({
    required final GameEngine engine,
    required final GameEngineState state,
    required final GameSnapshot snapshot,
    required final String playerId,
    required final SchupfAction chosen,
  }) async {
    final hand = List<Card>.from(snapshot.hands[playerId] ?? const <Card>[]);
    if (hand.length < 3) return;
    final candidates = _schupfCandidates(playerId, hand, chosen);
    final me = state.players.firstWhere((final p) => p.id == playerId);
    final team = me.seat % 2;
    final partnerId = state.players
        .firstWhere((final p) => p.seat == (me.seat + 2) % 4)
        .id;
    final outcomes = <List<int>?>[];
    for (final candidate in candidates) {
      final fork = state.copy();
      final agents = {
        for (final p in fork.players) p.id: agentFactory(p.id, p.seat),
      };
      try {
        engine.applyAction(fork, candidate);
        // Agents signal "no legal action" with StateError.
        // ignore: avoid_catching_errors
      } on StateError {
        outcomes.add(null);
        continue;
      }
      final diff = await _playOutRound(engine, fork, agents);
      if (diff == null) {
        outcomes.add(null);
        continue;
      }
      final score = fork.scoreTracker.state;
      final order = score.finishOrder;
      int teamOf(final String id) =>
          fork.players.firstWhere((final p) => p.id == id).seat % 2;
      final firstMine = order.isNotEmpty && teamOf(order.first) == team;
      final doubleWin =
          order.length >= 2 && teamOf(order[0]) == teamOf(order[1]);
      int callCode(final String id) {
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
