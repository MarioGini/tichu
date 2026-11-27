part of 'headless.dart';

/// Emits one JSONL row per (state, action) decision the trained policy needs.
///
/// This is a minimal-by-design writer: it skips everything BC training does
/// not consume (raw observations, reward breakdowns, both state keys, etc.)
/// to keep the JSONL small and fast to write.
///
/// One row per play-phase decision where the actor has more than one legal
/// action and chose either a play or a pass. Rows look like:
///   {"episode": 1, "round": 2, "team": 0,
///    "state_features": [...stateFeatureCount floats...],
///    "legal_play_action_features": [[...actionFeatureCount...], ...],
///    "legal_play_chosen_index": 3}
///
/// The legal set is exactly what `NnPlaySelectionStrategy` scores at
/// inference: wish-filtered legal plays, plus pass when legal.
///
/// Decisions taken by ε-exploration are flagged `"explore": true` so BC can
/// skip them (they are not the behaviour policy's choice).
///
/// Bookkeeping rows carry no features:
///   {"episode": 1, "round_end": true, "round": 2,
///    "team_one_round": 35, "team_two_round": 65}
///   {"episode": 1, "episode_end": true, "winner": 0,
///    "team_one_total": 1005, "team_two_total": 870}
class _BcTransitionWriter {
  final IOSink output;
  final int episode;

  /// Index of the next action in this round's game record
  /// (`--record-games`); written on play rows as `step`.
  int? step;

  _BcTransitionWriter({required this.output, required this.episode});

  /// One row per explored/logged Tichu or Grand Tichu decision:
  ///   {"episode", "round", "team", "call": "tichu"|"grand",
  ///    "called": bool, "explore": bool, "state_features": [...]}
  void emitCallDecision({
    required String kind,
    required GameSnapshot snapshot,
    required String playerId,
    required bool called,
    required bool explored,
    double? counterfactual,
    Map<String, Object?>? cfDetails,
  }) {
    output.writeln(
      jsonEncode(<String, Object?>{
        'episode': episode,
        'round': snapshot.scoreState.roundNumber,
        'team': _teamForPlayer(snapshot, playerId),
        'call': kind,
        // Exact R(call) - R(no call) for this deal, in points (optional).
        'cf': ?counterfactual,
        if (counterfactual != null && cfDetails != null) ...cfDetails,
        'seat': snapshot.players.firstWhere((p) => p.id == playerId).seat,
        // Heuristic hand strength (for calibrating the call threshold).
        'strength': DefaultTichuCallStrategy.tichuStrength(
          snapshot.hands[playerId] ?? const <Card>[],
        ),
        'opp_called': snapshot.players.any(
          (p) =>
              p.seat % 2 !=
                  snapshot.players.firstWhere((q) => q.id == playerId).seat %
                      2 &&
              (snapshot.scoreState.tichuCalls[p.id] ?? TichuCall.none) !=
                  TichuCall.none,
        ),
        'hand': [
          for (final c in snapshot.hands[playerId] ?? const <Card>[])
            cardSlot(c),
        ],
        'oracle': _oracle(snapshot, playerId),
        'called': called,
        if (explored) 'explore': true,
        'state_features': encodeStateFeatures(
          snapshot: snapshot,
          playerId: playerId,
        ),
        // Received schupf cards [from left, partner, right] (-1 = none yet).
        'received': [
          for (final (_, card) in receivedSchupfCards(snapshot, playerId))
            if (card == null) -1 else cardSlot(card),
        ],
      }),
    );
  }

  /// One row per schupf decision (features built in Python from it, see
  /// `SchupfFeatures`):
  ///   {"episode", "round", "team", "schupf": true, "hand": [slots...],
  ///    "left": slot, "partner": slot, "right": slot,
  ///    "context": [gt, tichu] × (me, partner, left, right), "explore"?}
  void emitSchupfDecision({
    required GameSnapshot snapshot,
    required SchupfAction action,
    required bool explored,
  }) {
    final hand = snapshot.hands[action.playerId] ?? const <Card>[];
    output.writeln(
      jsonEncode(<String, Object?>{
        'episode': episode,
        'round': snapshot.scoreState.roundNumber,
        'team': _teamForPlayer(snapshot, action.playerId),
        'schupf': true,
        'oracle': _oracle(snapshot, action.playerId),
        'hand': [for (final c in hand) cardSlot(c)],
        'left': cardSlot(action.toLeft),
        'partner': cardSlot(action.toPartner),
        'right': cardSlot(action.toRight),
        'context': SchupfFeatures.context(snapshot, action.playerId),
        if (explored) 'explore': true,
      }),
    );
  }

  /// One row per labelled schupf decision (`--schupf-rollout-rate`): the
  /// pre-exchange hands of all four players (me, left, partner, right),
  /// the candidate passes ([left, partner, right] slots; index 0 = the
  /// bot's own choice) and their exact outcomes (see `_labelSchupf`).
  void emitSchupfLabels({
    required GameSnapshot snapshot,
    required String playerId,
    required List<SchupfAction> candidates,
    required List<List<int>?> outcomes,
  }) {
    final table = TableRelationships(snapshot, playerId);
    List<int> slots(String? id) => [
      for (final c in snapshot.hands[id] ?? const <Card>[]) cardSlot(c),
    ];
    output.writeln(
      jsonEncode(<String, Object?>{
        'episode': episode,
        'round': snapshot.scoreState.roundNumber,
        'team': _teamForPlayer(snapshot, playerId),
        'schupf_cf': true,
        'hands': [
          slots(playerId),
          slots(table.playerBySeat(table.leftSeat()).id),
          slots(table.partnerId),
          slots(table.playerBySeat(table.rightSeat()).id),
        ],
        'context': SchupfFeatures.context(snapshot, playerId),
        'cands': [
          for (final a in candidates)
            [cardSlot(a.toLeft), cardSlot(a.toPartner), cardSlot(a.toRight)],
        ],
        'out': outcomes,
      }),
    );
  }

  /// One row per labelled Dragon gift or Mah Jong wish
  /// (`--side-rollout-rate`, see `_labelSideDecision`).
  void emitSideDecision({
    required String kind,
    required GameSnapshot snapshot,
    required String playerId,
    required List<Object> options,
    required List<double?> values,
    required int chosen,
    required int trickPoints,
  }) {
    final score = snapshot.scoreState;
    output.writeln(
      jsonEncode(<String, Object?>{
        'episode': episode,
        'round': score.roundNumber,
        'team': _teamForPlayer(snapshot, playerId),
        'side': kind,
        'seat': snapshot.players.firstWhere((p) => p.id == playerId).seat,
        'options': options,
        'values': values,
        'chosen': chosen,
        if (kind == 'dragon') 'trick_points': trickPoints,
        // Per seat: cards in hand, card points won so far, call (0/1/2),
        // finishing position (0 = still in).
        'cards_by_seat': [
          for (var seat = 0; seat < 4; seat++)
            (snapshot.hands[_idAt(snapshot, seat)] ?? const <Card>[]).length,
        ],
        'points_by_seat': [
          for (var seat = 0; seat < 4; seat++)
            score.playerRoundPoints[_idAt(snapshot, seat)] ?? 0,
        ],
        'call_by_seat': [
          for (var seat = 0; seat < 4; seat++)
            switch (score.tichuCalls[_idAt(snapshot, seat)]) {
              TichuCall.tichu => 1,
              TichuCall.grandTichu => 2,
              _ => 0,
            },
        ],
        'finish_seats': [
          for (final id in score.finishOrder)
            snapshot.players.firstWhere((p) => p.id == id).seat,
        ],
        'hand': [
          for (final c in snapshot.hands[playerId] ?? const <Card>[])
            cardSlot(c),
        ],
        'state_features': encodeStateFeatures(
          snapshot: snapshot,
          playerId: playerId,
        ),
      }),
    );
  }

  String _idAt(GameSnapshot snapshot, int seat) =>
      snapshot.players.firstWhere((p) => p.seat == seat).id;

  void emitRoundEnd(GameSnapshot after, {Map<int, int>? cardsLeftAtFirstOut}) {
    final score = after.scoreState;
    output.writeln(
      jsonEncode(<String, Object?>{
        'episode': episode,
        'round_end': true,
        'round': score.roundNumber,
        'team_one_round': score.teamOneRound,
        'team_two_round': score.teamTwoRound,
        // Card points of the tricks each seat won (before the last player's
        // tricks go to the first player), and the card points left in the
        // last player's hand (they go to the opposing team).
        'trick_points_by_seat': [
          for (var seat = 0; seat < 4; seat++)
            score.playerRoundPoints[after.players
                    .firstWhere((p) => p.seat == seat)
                    .id] ??
                0,
        ],
        if (score.finishOrder.isNotEmpty)
          'last_hand_points': pointsForCards(
            after.hands[score.finishOrder.last] ?? const <Card>[],
          ),
        // Teams (0 = even seats) in finishing order, for analysis.
        'finish_teams': [
          for (final id in score.finishOrder) _teamForPlayer(after, id),
        ],
        'finish_seats': [
          for (final id in score.finishOrder)
            after.players.firstWhere((p) => p.id == id).seat,
        ],
        // Cards each seat still held when the first player went out.
        if (cardsLeftAtFirstOut != null)
          'cards_left_at_first_out': [
            for (var seat = 0; seat < 4; seat++) cardsLeftAtFirstOut[seat] ?? 0,
          ],
        // Calls as [team, "tichu"|"grandTichu", succeeded (went out first)].
        'calls': [
          for (final e in score.tichuCalls.entries)
            if (e.value != TichuCall.none)
              [
                _teamForPlayer(after, e.key),
                e.value.name,
                score.finishOrder.isNotEmpty &&
                    score.finishOrder.first == e.key,
                after.players.firstWhere((p) => p.id == e.key).seat,
              ],
        ],
      }),
    );
  }

  void emitEpisodeEnd(GameSnapshot snapshot) {
    final score = snapshot.scoreState;
    output.writeln(
      jsonEncode(<String, Object?>{
        'episode': episode,
        'episode_end': true,
        'done': score.gameComplete,
        'winner': score.winningTeam,
        'team_one_total': score.teamOneTotal,
        'team_two_total': score.teamTwoTotal,
      }),
    );
  }

  void emitTransition({
    required GameSnapshot before,
    required GameAction action,
    required bool explored,
    GameAction? shadow,
    List<double?>? rollouts,
    List<double?>? rolloutsOwn,
    List<List<double?>>? rolloutWorlds,
    bool describe = false,
    List<GameAction?>? variants,
  }) {
    if (before.phase != GamePhase.play) return;
    if (before.currentPlayerId != action.playerId) return;
    if (action is! PlayTurnAction && action is! PassAction) return;

    final legalPlayFeatures = _legalPlayActionFeatures(
      snapshot: before,
      chosen: action,
      shadow: shadow,
    );
    if (legalPlayFeatures == null) return;

    final actorTeam = _teamForPlayer(before, action.playerId);
    final stateFeatures = encodeStateFeatures(
      snapshot: before,
      playerId: action.playerId,
    );

    final record = <String, Object?>{
      'episode': episode,
      'round': before.scoreState.roundNumber,
      'step': ?step,
      'team': actorTeam,
      'seat': before.players.firstWhere((p) => p.id == action.playerId).seat,
      if (explored) 'explore': true,
      'state_features': stateFeatures,
      'oracle': _oracle(before, action.playerId),
      'legal_play_action_features': legalPlayFeatures.features,
      'legal_play_chosen_index': legalPlayFeatures.chosenIndex,
      // --rollout-rate: exact round result (actor's team) after each legal
      // action, same order as the features; null = not rolled out.
      if (rollouts != null &&
          rollouts.length == legalPlayFeatures.features.length)
        'q_rollout': rollouts,
      // The actor's team's own round points in the same rollouts.
      if (rolloutsOwn != null &&
          rolloutsOwn.length == legalPlayFeatures.features.length)
        'q_rollout_own': rolloutsOwn,
      // --rollout-worlds: the same actions rolled out in re-dealt worlds.
      if (rolloutWorlds != null && rolloutWorlds.isNotEmpty)
        'q_rollout_worlds': rolloutWorlds,
      if (describe) 'desc': _describePosition(before, action.playerId),
      // --shadow-heuristics: index each variant would have chosen (-1 = n/a).
      if (variants != null)
        'shadow_indices': [
          for (final v in variants) _indexOf(legalPlayFeatures.keys, v),
        ],
      // --shadow-heuristic: what the heuristic would have done here.
      if (shadow != null) ...{
        'shadow_index': legalPlayFeatures.shadowIndex,
        'leading':
            before.deck.turn.type == TurnType.empty ||
            before.deck.turn.type == TurnType.none,
        'trick_type': before.deck.turn.type.name,
        'chosen_desc': _describe(action),
        'shadow_desc': _describe(shadow),
        'hand_size': (before.hands[action.playerId] ?? const <Card>[]).length,
      },
    };
    output.writeln(jsonEncode(record));
  }

  /// Perfect-information features for training only (PerfectDou-style
  /// oracle critic): card slots of the left opponent's, partner's and right
  /// opponent's current hands. Never used by the acting policy.
  List<List<int>> _oracle(GameSnapshot snapshot, String playerId) {
    final table = TableRelationships(snapshot, playerId);
    final ids = [
      table.playerBySeat(table.leftSeat()).id,
      table.partnerId,
      table.playerBySeat(table.rightSeat()).id,
    ];
    return [
      for (final id in ids)
        [for (final c in snapshot.hands[id] ?? const <Card>[]) cardSlot(c)],
    ];
  }

  int _teamForPlayer(GameSnapshot snapshot, String playerId) {
    final player = snapshot.players.firstWhere(
      (p) => p.id == playerId,
      orElse: () => snapshot.players.first,
    );
    return player.seat.isEven ? 0 : 1;
  }
}
