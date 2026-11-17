part of 'headless.dart';

/// Exploration and exact counterfactual labels for training data.
extension _Exploration on _HeadlessSimulator {
  /// Exact value of calling Tichu now for [playerId]'s team, in round
  /// points: the round is forked and played out twice with fresh,
  /// non-exploring agents — once with the call, once with the player never
  /// calling this round — and the team's point differences are subtracted.
  /// The deal is fixed and the bots are deterministic, so this label has no
  /// card-luck noise at all.
  ///
  /// [kind]: 'tichu' (play phase; the no-call branch never calls this
  /// round), 'grand' (Grand Tichu decision; no-call = declines, then plays
  /// on normally) or 'pre' (before the schupf; no-call = continues
  /// normally, may still call Tichu later).
  Future<double?> _counterfactualCall(
    final GameEngine engine,
    final GameEngineState state,
    final String playerId,
    final String kind,
  ) async {
    final team =
        state.players.firstWhere((final p) => p.id == playerId).seat % 2;
    Future<(int, bool)?> playOut({required final bool call}) async {
      final fork = state.copy();
      final forkAgents = {
        for (final p in fork.players) p.id: agentFactory(p.id, p.seat),
      };
      final preDecided = {..._preSchupfDecided};
      if (kind == 'grand') {
        engine.applyAction(
          fork,
          GrandTichuDecisionAction(playerId: playerId, call: call),
        );
      } else if (call) {
        engine.applyAction(fork, CallTichuAction(playerId: playerId));
      }
      if (kind == 'pre') preDecided.add(playerId);
      for (var steps = 0; steps < 5000; steps++) {
        final score = fork.scoreTracker.state;
        if (score.roundComplete) {
          final diff = score.teamOneRound - score.teamTwoRound;
          final first =
              score.finishOrder.isNotEmpty &&
              score.finishOrder.first == playerId;
          return (team == 0 ? diff : -diff, first);
        }
        final request = AgentDecisions.next(
          engine,
          fork,
          preSchupfDecided: preDecided,
        );
        if (request == null) return null;
        if (request is PreSchupfTichuRequest) preDecided.add(request.playerId);
        final agent = forkAgents[request.playerId]!;
        final snap = engine.buildSnapshot(fork);
        GameAction? action;
        try {
          // The decider keeps the counterfactual: no Tichu in the
          // no-call branch (selectTurn never calls).
          action =
              kind == 'tichu' &&
                  request is TurnRequest &&
                  request.playerId == playerId
              ? await agent.selectTurn(snap)
              : await AgentDecisions.resolve(request, agent, snap, fork);
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

    _lastCallDetails = null;
    final withCall = await playOut(call: true);
    final without = await playOut(call: false);
    if (withCall == null || without == null) return null;
    // Ground truth of both branches for success / strength models: round
    // points (own team) and whether this player went out first.
    _lastCallDetails = {
      'call_points': withCall.$1,
      'call_first': withCall.$2,
      'nocall_points': without.$1,
      'nocall_first': without.$2,
    };
    return (withCall.$1 - without.$1).toDouble();
  }

  /// Replace one to three (mostly one) of the passed cards with random other
  /// hand cards, and sometimes swap destinations.
  SchupfAction _perturbSchupf(final SchupfAction base, final List<Card> hand) {
    final chosen = [base.toLeft, base.toPartner, base.toRight];
    // Mostly small changes, so the data covers choices near the heuristic's.
    final roll = random.nextDouble();
    final changes = roll < 0.7 ? 1 : (roll < 0.95 ? 2 : 3);
    final slots = [0, 1, 2]..shuffle(random);
    for (final slot in slots.take(changes)) {
      // Stay within the bomb-safety convention for the opponents' cards.
      final pool = [
        for (final c in hand)
          if (!chosen.any((final x) => _sameCard(x, c)) &&
              (slot != 0 || SchupfFeatures.allowedLeft(c)) &&
              (slot != 2 || SchupfFeatures.allowedRight(c)))
            c,
      ];
      if (pool.isEmpty) break;
      chosen[slot] = pool[random.nextInt(pool.length)];
    }
    if (random.nextBool()) {
      // Also explore who gets which card.
      final a = random.nextInt(3);
      final b = random.nextInt(3);
      final swapped = [...chosen];
      swapped[a] = chosen[b];
      swapped[b] = chosen[a];
      if (SchupfFeatures.allowedLeft(swapped[0]) &&
          SchupfFeatures.allowedRight(swapped[2])) {
        chosen
          ..clear()
          ..addAll(swapped);
      }
    }
    return SchupfAction(
      playerId: base.playerId,
      toLeft: chosen[0],
      toPartner: chosen[1],
      toRight: chosen[2],
    );
  }

  bool _sameCard(final Card a, final Card b) =>
      a.face == b.face && a.color == b.color;

  GameAction? _pickRandomLegalAction(
    final GameSnapshot snapshot,
    final String playerId,
  ) {
    final hand = List<Card>.from(snapshot.hands[playerId] ?? const <Card>[]);
    if (hand.isEmpty) return null;

    final legalTurns = generateLegalTurns(snapshot.deck, List<Card>.from(hand));

    // Honour any active wish: if the wish must be fulfilled and this turn
    // doesn't fulfil it, skip it. mahJong() returns true when the wish is
    // active and the turn fails to satisfy it.
    final wishFiltered = <TichuTurn>[
      for (final turn in legalTurns)
        if (!mahJong(snapshot.deck, turn, hand)) turn,
    ];

    // Pass legality also requires non-empty deck and that the wish (if any)
    // does not need to be fulfilled by this player on this turn.
    final canPass =
        snapshot.deck.turn.type != TurnType.empty &&
        snapshot.deck.turn.type != TurnType.none &&
        !mahJong(snapshot.deck, TichuTurn(TurnType.none, const []), hand);

    final actions = <GameAction>[
      for (final turn in wishFiltered)
        PlayTurnAction(playerId: playerId, cards: List<Card>.from(turn.cards)),
      if (canPass) PassAction(playerId: playerId),
    ];

    if (actions.isEmpty) return null;
    return actions[random.nextInt(actions.length)];
  }
}
