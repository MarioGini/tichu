part of 'headless.dart';

class _CsvEventWriter {
  final IOSink output;
  final bool includeTimestamps;

  GameSnapshot? _previous;
  var _sequence = 0;
  var _headerWritten = false;

  _CsvEventWriter({required this.output, required this.includeTimestamps});

  void processSnapshot(final GameSnapshot snapshot) {
    if (!_headerWritten) {
      _writeHeader();
      _headerWritten = true;
    }

    if (_previous == null) {
      _emitGameStart(snapshot);
      _emitRoundStart(snapshot);
      _previous = snapshot;
      return;
    }

    _emitGrandTichuDecisions(snapshot, _previous!);
    _emitSchupfReceipts(snapshot, _previous!);
    _emitTurnResolution(snapshot, _previous!);
    _emitDragonGive(snapshot, _previous!);
    _emitRoundEnd(snapshot, _previous!);
    _emitGameEnd(snapshot, _previous!);

    _previous = snapshot;
  }

  void emitOpponentAction({
    required final GameSnapshot snapshot,
    required final GameAction action,
  }) {
    if (action is PlayTurnAction) {
      _writeRow(
        event: 'opponent_action',
        snapshot: snapshot,
        playerId: action.playerId,
        action: 'play',
        cards: action.cards,
      );
      return;
    }

    if (action is PassAction) {
      _writeRow(
        event: 'opponent_action',
        snapshot: snapshot,
        playerId: action.playerId,
        action: 'pass',
      );
    }
  }

  void _emitGameStart(final GameSnapshot snapshot) {
    final players = snapshot.players
        .map((final p) => '${p.id}:${p.seat}:${p.type.name}')
        .join('|');
    _writeRow(event: 'game_start', snapshot: snapshot, note: players);
  }

  void _emitRoundStart(final GameSnapshot snapshot) {
    _writeRow(event: 'round_start', snapshot: snapshot);
    for (final entry in snapshot.hands.entries) {
      _writeRow(
        event: 'initial_hand',
        snapshot: snapshot,
        playerId: entry.key,
        cards: entry.value,
      );
    }
  }

  void _emitGrandTichuDecisions(
    final GameSnapshot snapshot,
    final GameSnapshot previous,
  ) {
    for (final entry in snapshot.grandTichuDecisions.entries) {
      if (previous.grandTichuDecisions.containsKey(entry.key)) continue;
      _writeRow(
        event: 'grand_tichu',
        snapshot: snapshot,
        playerId: entry.key,
        action: entry.value ? 'call' : 'pass',
      );
    }

    if (previous.scoreState.roundNumber != snapshot.scoreState.roundNumber) {
      _emitRoundStart(snapshot);
    }
  }

  void _emitSchupfReceipts(
    final GameSnapshot snapshot,
    final GameSnapshot previous,
  ) {
    if (previous.phase == GamePhase.schupf &&
        snapshot.phase == GamePhase.play) {
      for (final entry in snapshot.schupfReceipts.entries) {
        final recipientId = entry.key;
        for (final receipt in entry.value) {
          _writeRow(
            event: 'schupf_receipt',
            snapshot: snapshot,
            playerId: recipientId,
            action: receipt.direction.name,
            cards: [receipt.card],
            note: receipt.fromPlayerId,
          );
        }
      }
    }
  }

  void _emitTurnResolution(
    final GameSnapshot snapshot,
    final GameSnapshot previous,
  ) {
    if (snapshot.lastPlayedTurn == null) return;
    if (previous.lastPlayedTurn == snapshot.lastPlayedTurn &&
        previous.lastPlayedBy == snapshot.lastPlayedBy) {
      return;
    }

    _writeRow(
      event: 'turn_resolved',
      snapshot: snapshot,
      playerId: snapshot.lastPlayedBy,
      action: snapshot.lastPlayedTurn!.type.name,
      cards: snapshot.lastPlayedTurn!.cards,
    );
  }

  void _emitDragonGive(
    final GameSnapshot snapshot,
    final GameSnapshot previous,
  ) {
    if (snapshot.lastDragonGiveBy == null ||
        snapshot.lastDragonGiveTo == null) {
      return;
    }
    if (snapshot.lastDragonGiveBy == previous.lastDragonGiveBy &&
        snapshot.lastDragonGiveTo == previous.lastDragonGiveTo) {
      return;
    }

    _writeRow(
      event: 'dragon_give',
      snapshot: snapshot,
      playerId: snapshot.lastDragonGiveBy,
      action: snapshot.lastDragonGiveTo,
    );
  }

  void _emitRoundEnd(
    final GameSnapshot snapshot,
    final GameSnapshot previous,
  ) {
    if (!snapshot.scoreState.roundComplete ||
        previous.scoreState.roundComplete) {
      return;
    }

    _writeRow(
      event: 'round_end',
      snapshot: snapshot,
      note: snapshot.scoreState.finishOrder.join('|'),
    );
  }

  void _emitGameEnd(
    final GameSnapshot snapshot,
    final GameSnapshot previous,
  ) {
    if (!snapshot.scoreState.gameComplete || previous.scoreState.gameComplete) {
      return;
    }

    _writeRow(
      event: 'game_end',
      snapshot: snapshot,
      note: snapshot.scoreState.winningTeam?.toString() ?? '',
    );
  }

  void _writeHeader() {
    output.writeln(
      'seq,ts_ms,game_id,round,phase,event,player_id,action,cards,'
      'deck_type,deck_value,active_wish,trick_points,'
      'team_one_round,team_two_round,team_one_total,team_two_total,'
      'round_complete,game_complete,note',
    );
  }

  void _writeRow({
    required final String event,
    required final GameSnapshot snapshot,
    final String? playerId,
    final String? action,
    final List<Card>? cards,
    final String? note,
  }) {
    final sequence = _sequence++;
    final ts = includeTimestamps ? DateTime.now().millisecondsSinceEpoch : 0;
    final row = [
      sequence.toString(),
      ts.toString(),
      snapshot.gameId,
      snapshot.scoreState.roundNumber.toString(),
      snapshot.phase.name,
      event,
      playerId ?? '',
      action ?? '',
      _formatCards(cards),
      snapshot.deck.turn.type.name,
      snapshot.deck.turn.value.toStringAsFixed(1),
      snapshot.activeWish.name,
      snapshot.trickPoints.toString(),
      snapshot.scoreState.teamOneRound.toString(),
      snapshot.scoreState.teamTwoRound.toString(),
      snapshot.scoreState.teamOneTotal.toString(),
      snapshot.scoreState.teamTwoTotal.toString(),
      snapshot.scoreState.roundComplete.toString(),
      snapshot.scoreState.gameComplete.toString(),
      note ?? '',
    ];

    output.writeln(row.map(_csvEscape).join(','));
  }

  String _csvEscape(final String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  String _formatCards(final List<Card>? cards) {
    if (cards == null || cards.isEmpty) return '';
    return cards.map(_cardToken).join('|');
  }
}
