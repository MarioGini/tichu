part of 'headless.dart';

/// Emits one JSONL row per (state, action) decision the trained policy needs.
///
/// This is a minimal-by-design writer: it skips everything BC training does
/// not consume (raw observations, reward breakdowns, both state keys, etc.)
/// to keep the JSONL small and fast to write.
///
/// One row per play-phase decision where the actor has more than one legal
/// action and chose either a play or a pass. Rows look like:
///   {"episode": 1, "team": 0,
///    "state_features": [...stateFeatureCount floats...],
///    "legal_play_action_features": [[...actionFeatureCount...], ...],
///    "legal_play_chosen_index": 3,
///    "done": true, "winner": 0,         // only on the very last row
///    "team_one_total": 105, "team_two_total": 95}
class _BcTransitionWriter {
  final IOSink output;
  final int episode;

  _BcTransitionWriter({required this.output, required this.episode});

  void emitTransition({
    required final GameSnapshot before,
    required final GameAction action,
    required final GameSnapshot after,
  }) {
    if (before.phase != GamePhase.play) return;
    if (before.currentPlayerId != action.playerId) return;
    if (action is! PlayTurnAction && action is! PassAction) return;

    final legalPlayFeatures = _legalPlayActionFeatures(
      snapshot: before,
      chosen: action,
    );
    if (legalPlayFeatures == null) return;

    final actorTeam = _teamForPlayer(before, action.playerId);
    final stateFeatures = encodeStateFeatures(
      snapshot: before,
      playerId: action.playerId,
    );

    final record = <String, Object?>{
      'episode': episode,
      'team': actorTeam,
      'state_features': stateFeatures,
      'legal_play_action_features': legalPlayFeatures.features,
      'legal_play_chosen_index': legalPlayFeatures.chosenIndex,
      if (after.scoreState.gameComplete) 'done': true,
      if (after.scoreState.gameComplete)
        'team_one_total': after.scoreState.teamOneTotal,
      if (after.scoreState.gameComplete)
        'team_two_total': after.scoreState.teamTwoTotal,
      if (after.scoreState.gameComplete) 'winner': after.scoreState.winningTeam,
    };
    output.writeln(jsonEncode(record));
  }

  int _teamForPlayer(final GameSnapshot snapshot, final String playerId) {
    final player = snapshot.players.firstWhere(
      (final p) => p.id == playerId,
      orElse: () => snapshot.players.first,
    );
    return player.seat.isEven ? 0 : 1;
  }

  bool _canPass(final GameSnapshot snapshot, final List<Card> hand) {
    if (snapshot.deck.turn.type == TurnType.empty ||
        snapshot.deck.turn.type == TurnType.none) {
      return false;
    }
    return !mahJong(snapshot.deck, TichuTurn(TurnType.none, const []), hand);
  }

  /// Encode action features for every legal play (plus pass when legal) and
  /// return them together with the index of the chosen action. Returns null
  /// when the chosen action cannot be located among the enumerated legal
  /// actions (defensive: should not happen in the play phase).
  ({List<List<double>> features, int chosenIndex})? _legalPlayActionFeatures({
    required final GameSnapshot snapshot,
    required final GameAction chosen,
  }) {
    final hand = List<Card>.from(
      snapshot.hands[chosen.playerId] ?? const <Card>[],
    );
    final legalTurns = generateLegalTurns(snapshot.deck, hand);
    final encoder = FeatureEncoder(
      snapshot: snapshot,
      playerId: chosen.playerId,
    );
    final canPass = _canPass(snapshot, hand);

    final features = <List<double>>[];
    var chosenIndex = -1;

    final chosenKey = chosen is PlayTurnAction ? _cardKey(chosen.cards) : null;
    for (final turn in legalTurns) {
      final feat = encoder.actionFeatures(turn);
      if (chosenIndex < 0 &&
          chosenKey != null &&
          _cardKey(turn.cards) == chosenKey) {
        chosenIndex = features.length;
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
      features.add(passFeat);
    }

    if (chosenIndex < 0) return null;
    return (features: features, chosenIndex: chosenIndex);
  }

  /// Order-independent identity of a card set (phoenix matches by face, so
  /// its assigned value does not matter).
  static String _cardKey(final List<Card> cards) {
    final slots = [for (final c in cards) cardSlot(c)]..sort();
    return slots.join(',');
  }
}
