import 'package:tichu/agents/table_relationships.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/find_turn.dart';
import 'package:tichu/game/turn/tichu_data.dart';

String encodeRlCardToken(final Card card) {
  if (card.face == CardFace.phoenix) {
    return 'phoenix:${card.value.toStringAsFixed(1)}';
  }
  return '${card.face.name}-${card.color.name}';
}

String encodeRlTurnKey(final TichuTurn turn) {
  final cards = [...turn.cards]..sort(compareCards);
  final tokens = cards.map(encodeRlCardToken).join('|');
  return '${turn.type.name}:${turn.value.toStringAsFixed(1)}:$tokens';
}

String encodeRlPlayActionKeyFromTurn(final TichuTurn turn) =>
    'play:${encodeRlTurnKey(turn)}';

String encodeRlPlayShapeKeyFromTurn(final TichuTurn turn) =>
    'play_shape:${turn.type.name}:${turn.value.toStringAsFixed(1)}:${turn.cards.length}';

String encodeRlPolicyPlayActionKey({
  required final TichuTurn turn,
  required final DeckState deck,
  required final int handSize,
}) {
  final isLeading =
      deck.turn.type == TurnType.empty ||
      deck.turn.type == TurnType.none ||
      deck.turn.type == TurnType.dog;
  final tempo = isLeading
      ? 'lead'
      : turn.type == TurnType.bomb
      ? 'bomb'
      : _responseMarginBucket(turn.value - deck.turn.value);
  return [
    'play_policy',
    turn.type.name,
    'n${turn.cards.length}',
    _valueBand(turn.value),
    tempo,
    turn.cards.length == handSize ? 'finish' : 'continue',
  ].join(':');
}

String encodeRlPlayShapeKeyFromCards(final List<Card> cards) {
  try {
    final turn = getTurn(List<Card>.from(cards));
    if (turn.type == TurnType.none) {
      return 'play_shape:unknown:${cards.length}';
    }
    return encodeRlPlayShapeKeyFromTurn(turn);
  } on Exception {
    return 'play_shape:unknown:${cards.length}';
  }
}

String encodeRlPlayActionKeyFromCards(final List<Card> cards) {
  try {
    final turn = getTurn(List<Card>.from(cards));
    if (turn.type == TurnType.none) {
      final tokens = [...cards]..sort(compareCards);
      return 'play:unknown:${tokens.map(encodeRlCardToken).join('|')}';
    }
    return encodeRlPlayActionKeyFromTurn(turn);
  } on Exception {
    final tokens = [...cards]..sort(compareCards);
    return 'play:unknown:${tokens.map(encodeRlCardToken).join('|')}';
  }
}

String encodeRlActionShapeKey(final GameAction action) {
  if (action is PlayTurnAction) {
    return encodeRlPlayShapeKeyFromCards(action.cards);
  }
  if (action is PassAction) return 'pass';
  if (action is GiveDragonAction) return 'dragon_give:any';
  if (action is AcknowledgeSchupfAction) return 'ack_schupf';
  if (action is SchupfAction) return 'schupf:any';
  if (action is CallTichuAction) return 'call_tichu';
  if (action is CallGrandTichuAction) return 'call_grand_tichu';
  if (action is GrandTichuDecisionAction) return 'grand_tichu:decision';
  if (action is ConfirmOpponentTurnAction) return 'confirm';
  return 'unknown';
}

String encodeRlActionKey(final GameAction action) {
  if (action is PlayTurnAction) {
    return encodeRlPlayActionKeyFromCards(action.cards);
  }
  if (action is PassAction) return 'pass';
  if (action is GiveDragonAction) return 'dragon_give:${action.targetPlayerId}';
  if (action is AcknowledgeSchupfAction) return 'ack_schupf';
  if (action is SchupfAction) {
    return 'schupf:${encodeRlCardToken(action.toLeft)}:${encodeRlCardToken(action.toPartner)}:${encodeRlCardToken(action.toRight)}';
  }
  if (action is CallTichuAction) return 'call_tichu';
  if (action is CallGrandTichuAction) return 'call_grand_tichu';
  if (action is GrandTichuDecisionAction) {
    return action.call ? 'grand_tichu:call' : 'grand_tichu:pass';
  }
  if (action is ConfirmOpponentTurnAction) return 'confirm';
  return 'unknown';
}

Map<String, Object?> buildRlObservation({
  required final GameSnapshot snapshot,
  required final String playerId,
}) {
  final player = snapshot.players.firstWhere(
    (final p) => p.id == playerId,
    orElse: () => snapshot.players.first,
  );
  final hand = [...(snapshot.hands[playerId] ?? const <Card>[])]
    ..sort(compareCards);
  final tichuCalls = _sortedTichuCalls(snapshot.scoreState.tichuCalls);
  final opponentCounts = _sortedOpponentCounts(snapshot, playerId);

  return {
    'player_id': playerId,
    'player_seat': player.seat,
    'team': player.seat.isEven ? 0 : 1,
    'phase': snapshot.phase.name,
    'current_player_id': snapshot.currentPlayerId,
    'hand': hand.map(encodeRlCardToken).toList(growable: false),
    'hand_size': hand.length,
    'opponent_card_counts': opponentCounts,
    'deck_type': snapshot.deck.turn.type.name,
    'deck_value': snapshot.deck.turn.value,
    'deck_cards': snapshot.deck.turn.cards
        .map(encodeRlCardToken)
        .toList(growable: false),
    'active_wish': snapshot.activeWish.name,
    'consecutive_passes': snapshot.consecutivePasses,
    'trick_points': snapshot.trickPoints,
    'can_call_tichu': snapshot.canCallTichuByPlayer[playerId] ?? false,
    'has_bomb': snapshot.hasBombByPlayer[playerId] ?? false,
    'can_bomb': snapshot.canBombByPlayer[playerId] ?? false,
    'score': {
      'round': snapshot.scoreState.roundNumber,
      'team_one_round': snapshot.scoreState.teamOneRound,
      'team_two_round': snapshot.scoreState.teamTwoRound,
      'team_one_total': snapshot.scoreState.teamOneTotal,
      'team_two_total': snapshot.scoreState.teamTwoTotal,
      'round_complete': snapshot.scoreState.roundComplete,
      'game_complete': snapshot.scoreState.gameComplete,
      'winning_team': snapshot.scoreState.winningTeam,
    },
    'tichu_calls': {
      for (final entry in tichuCalls.entries) entry.key: entry.value.name,
    },
  };
}

String buildRlStateKey({
  required final GameSnapshot snapshot,
  required final String playerId,
}) {
  final hand = [...(snapshot.hands[playerId] ?? const <Card>[])]
    ..sort(compareCards);
  final handKey = hand.map(encodeRlCardToken).join('.');
  final oppKey = _sortedOpponentCounts(
    snapshot,
    playerId,
  ).entries.map((final e) => '${e.key}:${e.value}').join(';');
  final callsKey = _sortedTichuCalls(
    snapshot.scoreState.tichuCalls,
  ).entries.map((final e) => '${e.key}:${e.value.name}').join(';');

  return [
    'player=$playerId',
    'phase=${snapshot.phase.name}',
    'current=${snapshot.currentPlayerId}',
    'deck=${encodeRlTurnKey(snapshot.deck.turn)}',
    'wish=${snapshot.activeWish.name}',
    'passes=${snapshot.consecutivePasses}',
    'hand=$handKey',
    'opp=$oppKey',
    'r=${snapshot.scoreState.roundNumber}',
    'round=${snapshot.scoreState.teamOneRound}:${snapshot.scoreState.teamTwoRound}',
    'tot=${snapshot.scoreState.teamOneTotal}:${snapshot.scoreState.teamTwoTotal}',
    'calls=$callsKey',
  ].join('|');
}

String buildRlCoarseStateKey({
  required final GameSnapshot snapshot,
  required final String playerId,
}) {
  final hand = snapshot.hands[playerId] ?? const <Card>[];
  final team = _teamForPlayer(snapshot, playerId);
  final ownScore = _teamScore(snapshot.scoreState, team);
  final oppScore = _teamScore(snapshot.scoreState, team == 0 ? 1 : 0);
  final scoreGapBucket = ((ownScore - oppScore) / 25).round().clamp(-20, 20);

  final table = TableRelationships(snapshot, playerId);
  final opponentCounts = table.opponents
      .map((final opponent) => snapshot.hands[opponent.id]?.length ?? 0)
      .toList();
  final nearestOpponent = opponentCounts.isEmpty
      ? 0
      : opponentCounts.reduce((final a, final b) => a < b ? a : b);
  final partnerCount = snapshot.hands[table.partnerId]?.length ?? 0;
  final activeWish = snapshot.activeWish;
  final hasWishInHand =
      activeWish != CardFace.none &&
      hand.any((final card) => card.face == activeWish);
  final trickWinnerRelation = _trickWinnerRelation(snapshot, playerId);
  final ownCall = snapshot.scoreState.tichuCalls[playerId] ?? TichuCall.none;
  final partnerCall =
      snapshot.scoreState.tichuCalls[table.partnerId ?? ''] ?? TichuCall.none;
  final anyOppCall = table.opponents.any(
    (final opp) =>
        (snapshot.scoreState.tichuCalls[opp.id] ?? TichuCall.none) !=
        TichuCall.none,
  );

  final callPressure = ownCall != TichuCall.none
      ? 'self'
      : partnerCall != TichuCall.none
      ? 'partner'
      : anyOppCall
      ? 'opponent'
      : 'none';
  final wishState = activeWish == CardFace.none
      ? 'none'
      : hasWishInHand
      ? 'have'
      : 'missing';
  final scorePosition = scoreGapBucket < -1
      ? 'behind'
      : scoreGapBucket > 1
      ? 'ahead'
      : 'close';
  final isLeading =
      snapshot.deck.turn.type == TurnType.empty ||
      snapshot.deck.turn.type == TurnType.none ||
      snapshot.deck.turn.type == TurnType.dog;

  return [
    'v=2',
    'mode=${isLeading ? 'lead' : 'follow'}',
    'deck=${snapshot.deck.turn.type.name}:${_valueBand(snapshot.deck.turn.value)}',
    'trick_win=$trickWinnerRelation',
    'wish=$wishState',
    'passes=${snapshot.consecutivePasses.clamp(0, 3)}',
    'hand=${_countBucket(hand.length)}',
    'bomb=${(snapshot.hasBombByPlayer[playerId] ?? false) ? 1 : 0}',
    'partner=${_countBucket(partnerCount)}',
    'opp_min=${_countBucket(nearestOpponent)}',
    'call=$callPressure',
    'gap=$scorePosition',
  ].join('|');
}

String _trickWinnerRelation(
  final GameSnapshot snapshot,
  final String playerId,
) {
  final winner = snapshot.deck.currentWinner;
  if (winner.isEmpty) return 'none';
  if (winner == playerId) return 'self';
  final table = TableRelationships(snapshot, playerId);
  if (table.isPartner(winner)) return 'partner';
  return 'opponent';
}

int _teamForPlayer(final GameSnapshot snapshot, final String playerId) {
  final player = snapshot.players.firstWhere(
    (final p) => p.id == playerId,
    orElse: () => snapshot.players.first,
  );
  return player.seat.isEven ? 0 : 1;
}

int _teamScore(final ScoreState scoreState, final int team) {
  if (team == 0) {
    return scoreState.teamOneTotal + scoreState.teamOneRound;
  }
  return scoreState.teamTwoTotal + scoreState.teamTwoRound;
}

String _valueBand(final double value) {
  if (value <= 0) return 'none';
  if (value <= 5) return 'low';
  if (value <= 9) return 'mid';
  if (value <= 12) return 'high';
  if (value <= 14) return 'top';
  return 'special';
}

String _responseMarginBucket(final double margin) {
  if (margin <= 1) return 'just';
  if (margin <= 3) return 'small';
  return 'large';
}

String _countBucket(final int count) {
  if (count <= 0) return '0';
  if (count <= 1) return '1';
  if (count <= 3) return '3';
  if (count <= 5) return '5';
  if (count <= 8) return '8';
  if (count <= 11) return '11';
  return '13';
}

Map<String, int> _sortedOpponentCounts(
  final GameSnapshot snapshot,
  final String playerId,
) {
  final entries =
      snapshot.hands.entries
          .where((final entry) => entry.key != playerId)
          .toList()
        ..sort((final a, final b) => a.key.compareTo(b.key));

  final counts = <String, int>{};
  for (final entry in entries) {
    counts[entry.key] = entry.value.length;
  }
  return counts;
}

Map<String, TichuCall> _sortedTichuCalls(final Map<String, TichuCall> calls) {
  final entries = calls.entries.toList()
    ..sort((final a, final b) => a.key.compareTo(b.key));

  final sorted = <String, TichuCall>{};
  for (final entry in entries) {
    sorted[entry.key] = entry.value;
  }
  return sorted;
}
