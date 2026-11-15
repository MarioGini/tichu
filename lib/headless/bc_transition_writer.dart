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

  _BcTransitionWriter({required this.output, required this.episode});

  /// One row per explored/logged Tichu or Grand Tichu decision:
  ///   {"episode", "round", "team", "call": "tichu"|"grand",
  ///    "called": bool, "explore": bool, "state_features": [...]}
  void emitCallDecision({
    required final String kind,
    required final GameSnapshot snapshot,
    required final String playerId,
    required final bool called,
    required final bool explored,
    final double? counterfactual,
  }) {
    output.writeln(
      jsonEncode(<String, Object?>{
        'episode': episode,
        'round': snapshot.scoreState.roundNumber,
        'team': _teamForPlayer(snapshot, playerId),
        'call': kind,
        // Exact R(call) - R(no call) for this deal, in points (optional).
        'cf': ?counterfactual,
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
    required final GameSnapshot snapshot,
    required final SchupfAction action,
    required final bool explored,
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

  void emitRoundEnd(final GameSnapshot after) {
    final score = after.scoreState;
    output.writeln(
      jsonEncode(<String, Object?>{
        'episode': episode,
        'round_end': true,
        'round': score.roundNumber,
        'team_one_round': score.teamOneRound,
        'team_two_round': score.teamTwoRound,
        // Teams (0 = even seats) in finishing order, for analysis.
        'finish_teams': [
          for (final id in score.finishOrder) _teamForPlayer(after, id),
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
              ],
        ],
      }),
    );
  }

  void emitEpisodeEnd(final GameSnapshot snapshot) {
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
    required final GameSnapshot before,
    required final GameAction action,
    required final bool explored,
    final GameAction? shadow,
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
      'team': actorTeam,
      if (explored) 'explore': true,
      'state_features': stateFeatures,
      'oracle': _oracle(before, action.playerId),
      'legal_play_action_features': legalPlayFeatures.features,
      'legal_play_chosen_index': legalPlayFeatures.chosenIndex,
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
  List<List<int>> _oracle(final GameSnapshot snapshot, final String playerId) {
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

  int _teamForPlayer(final GameSnapshot snapshot, final String playerId) {
    final player = snapshot.players.firstWhere(
      (final p) => p.id == playerId,
      orElse: () => snapshot.players.first,
    );
    return player.seat.isEven ? 0 : 1;
  }

  /// Encode action features for every legal play (plus pass when legal) and
  /// return them together with the index of the chosen action. Returns null
  /// when the chosen action cannot be located among the enumerated legal
  /// actions (defensive: should not happen in the play phase).
  ({List<List<double>> features, int chosenIndex, int shadowIndex})?
  _legalPlayActionFeatures({
    required final GameSnapshot snapshot,
    required final GameAction chosen,
    final GameAction? shadow,
  }) {
    final hand = List<Card>.from(
      snapshot.hands[chosen.playerId] ?? const <Card>[],
    );
    final legalTurns = LegalPlayGuard.filterMoveGeneratorTurns(
      deck: snapshot.deck,
      hand: hand,
      moveGeneratorTurns: generateLegalTurns(snapshot.deck, hand),
    );
    final encoder = FeatureEncoder(
      snapshot: snapshot,
      playerId: chosen.playerId,
    );
    final canPass = LegalPlayGuard.canPass(deck: snapshot.deck, hand: hand);

    final features = <List<double>>[];
    var chosenIndex = -1;
    var shadowIndex = -1;

    final chosenKey = chosen is PlayTurnAction ? _cardKey(chosen.cards) : null;
    final shadowKey = shadow is PlayTurnAction ? _cardKey(shadow.cards) : null;
    for (final turn in legalTurns) {
      final feat = encoder.actionFeatures(turn);
      final key = _cardKey(turn.cards);
      if (chosenIndex < 0 && chosenKey != null && key == chosenKey) {
        chosenIndex = features.length;
      }
      if (shadowIndex < 0 && shadowKey != null && key == shadowKey) {
        shadowIndex = features.length;
      }
      features.add(feat);
    }

    if (canPass) {
      final passFeat = encoder.actionFeatures(
        TichuTurn(TurnType.none, const <Card>[]),
        isPass: true,
      );
      if (chosenIndex < 0 && chosen is PassAction) {
        chosenIndex = features.length;
      }
      if (shadowIndex < 0 && shadow is PassAction) {
        shadowIndex = features.length;
      }
      features.add(passFeat);
    }

    if (chosenIndex < 0) return null;
    return (
      features: features,
      chosenIndex: chosenIndex,
      shadowIndex: shadowIndex,
    );
  }

  static String _describe(final GameAction action) {
    if (action is PassAction) return 'pass';
    if (action is! PlayTurnAction) return action.runtimeType.toString();
    final cards = [for (final c in action.cards) c.face.name]..sort();
    return cards.join('+');
  }

  /// Order-independent identity of a card set (phoenix matches by face, so
  /// its assigned value does not matter).
  static String _cardKey(final List<Card> cards) {
    final slots = [for (final c in cards) cardSlot(c)]..sort();
    return slots.join(',');
  }
}
