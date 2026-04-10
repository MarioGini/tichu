part of 'headless.dart';

class _RewardResult {
  final double total;
  final Map<String, double> breakdown;

  const _RewardResult({required this.total, required this.breakdown});
}

class _RlTransitionWriter {
  final IOSink output;
  final int episode;
  final bool includeLegalTurnCount;

  var _sequence = 0;

  _RlTransitionWriter({
    required this.output,
    required this.episode,
    required this.includeLegalTurnCount,
  });

  void emitTransition({
    required final GameSnapshot before,
    required final GameAction action,
    required final GameSnapshot after,
    required final int step,
  }) {
    final actorTeam = _teamForPlayer(before, action.playerId);
    final rewardResult = _computeReward(
      actorTeam: actorTeam,
      action: action,
      before: before,
      after: after,
    );
    final reward = rewardResult.total;
    final actionKey = encodeRlActionKey(action);
    final actionShapeKey = encodeRlActionShapeKey(action);
    final stateKey = buildRlStateKey(
      snapshot: before,
      playerId: action.playerId,
    );
    final stateKeyCoarse = buildRlCoarseStateKey(
      snapshot: before,
      playerId: action.playerId,
    );
    final nextStateKey = buildRlStateKey(
      snapshot: after,
      playerId: action.playerId,
    );
    final nextStateKeyCoarse = buildRlCoarseStateKey(
      snapshot: after,
      playerId: action.playerId,
    );
    final stateObs = buildRlObservation(
      snapshot: before,
      playerId: action.playerId,
    );
    final nextStateObs = buildRlObservation(
      snapshot: after,
      playerId: action.playerId,
    );
    final legalActionKeys = _legalActionKeys(before, action.playerId);
    final actionIndex = legalActionKeys?.indexOf(actionKey);

    final legalTurnCount = includeLegalTurnCount
        ? _computeLegalTurnCount(before, action.playerId)
        : null;

    final record = <String, Object?>{
      'episode': episode,
      'seq': _sequence++,
      'step': step,
      'state_key': stateKey,
      'state_key_coarse': stateKeyCoarse,
      'next_state_key': nextStateKey,
      'next_state_key_coarse': nextStateKeyCoarse,
      'state': stateObs,
      'next_state': nextStateObs,
      'action_key': actionKey,
      'action_shape_key': actionShapeKey,
      'action': _actionPayload(action),
      'legal_action_keys': legalActionKeys,
      'legal_actions_enumerated': legalActionKeys != null,
      'action_index':
          actionIndex != null && actionIndex >= 0 ? actionIndex : null,
      'player_id': action.playerId,
      'team': actorTeam,
      'phase': before.phase.name,
      'action_type': _actionType(action),
      'cards': _cardsForAction(action).map(_cardToken).toList(growable: false),
      'input_wish': action is PlayTurnAction ? action.inputWish.name : null,
      'grand_tichu_call':
          action is GrandTichuDecisionAction ? action.call : null,
      'dragon_target':
          action is GiveDragonAction ? action.targetPlayerId : null,
      'reward': reward,
      'reward_breakdown': rewardResult.breakdown,
      'done': after.scoreState.gameComplete,
      'discount': after.scoreState.gameComplete ? 0.0 : 1.0,
      'round': after.scoreState.roundNumber,
      'team_one_round': after.scoreState.teamOneRound,
      'team_two_round': after.scoreState.teamTwoRound,
      'team_one_total': after.scoreState.teamOneTotal,
      'team_two_total': after.scoreState.teamTwoTotal,
      'current_player_id': after.currentPlayerId,
      'deck_type': after.deck.turn.type.name,
      'deck_value': after.deck.turn.value,
      'active_wish': after.activeWish.name,
      'hand_size': (after.hands[action.playerId] ?? const <Card>[]).length,
      'opponent_card_counts': _opponentCounts(after, action.playerId),
      'legal_turn_count': legalTurnCount,
    };
    record.removeWhere((final _, final value) => value == null);
    output.writeln(jsonEncode(record));
  }

  Map<String, Object?> _actionPayload(final GameAction action) {
    final payload = <String, Object?>{
      'type': _actionType(action),
      'player_id': action.playerId,
      'key': encodeRlActionKey(action),
      'shape_key': encodeRlActionShapeKey(action),
    };

    if (action is PlayTurnAction) {
      payload['cards'] = action.cards.map(_cardToken).toList(growable: false);
      payload['wish'] = action.inputWish.name;
    } else if (action is SchupfAction) {
      payload['to_left'] = _cardToken(action.toLeft);
      payload['to_partner'] = _cardToken(action.toPartner);
      payload['to_right'] = _cardToken(action.toRight);
    } else if (action is GiveDragonAction) {
      payload['target_player_id'] = action.targetPlayerId;
    } else if (action is GrandTichuDecisionAction) {
      payload['call'] = action.call;
    }

    return payload;
  }

  int _teamForPlayer(final GameSnapshot snapshot, final String playerId) {
    final player = snapshot.players.firstWhere(
      (final p) => p.id == playerId,
      orElse: () => snapshot.players.first,
    );
    return player.seat.isEven ? 0 : 1;
  }

  _RewardResult _computeReward({
    required final int actorTeam,
    required final GameAction action,
    required final GameSnapshot before,
    required final GameSnapshot after,
  }) {
    final breakdown = <String, double>{};

    final playerId = action.playerId;
    final beforeHand = before.hands[playerId] ?? const <Card>[];
    final afterHand = after.hands[playerId] ?? const <Card>[];
    final beforeHandSize = beforeHand.length;
    final afterHandSize = afterHand.length;

    final scoreDelta = _scoreDelta(
      actorTeam: actorTeam,
      before: before.scoreState,
      after: after.scoreState,
    );
    breakdown['score_delta'] = scoreDelta;

    var finishReward = 0.0;
    if (afterHandSize == 0 && beforeHandSize > 0) {
      final finishPosition = after.scoreState.finishOrder.indexOf(playerId);
      if (finishPosition >= 0) {
        const finishRewards = [10.0, 5.0, 1.0, -5.0];
        finishReward = finishRewards[finishPosition.clamp(0, 3)];
      } else {
        finishReward = 8.0;
      }
    }
    breakdown['finish_order'] = finishReward;

    var tichuReward = 0.0;
    final ownCall = before.scoreState.tichuCalls[playerId] ?? TichuCall.none;
    if (ownCall != TichuCall.none && after.scoreState.roundComplete) {
      final madeIt = after.scoreState.finishOrder.isNotEmpty &&
          after.scoreState.finishOrder.first == playerId;
      final bonus = ownCall == TichuCall.grandTichu ? 20.0 : 10.0;
      tichuReward = madeIt ? bonus : -bonus;
    }
    breakdown['tichu_outcome'] = tichuReward;

    final total = scoreDelta + finishReward + tichuReward;

    final cardsShed = beforeHandSize - afterHandSize;
    breakdown['cards_shed_diag'] = cardsShed > 0 ? cardsShed * 1.0 : 0.0;

    if (afterHandSize > 0 && cardsShed > 0) {
      final beforePlayability = _handPlayability(beforeHand);
      final afterPlayability = _handPlayability(afterHand);
      breakdown['playability_diag'] =
          (afterPlayability - beforePlayability) * 2.0;
    } else {
      breakdown['playability_diag'] = 0.0;
    }

    if (afterHandSize > 0 && beforeHandSize > 0 && cardsShed > 0) {
      final beforeStrength = HandEvaluator.evaluate(
        List<Card>.from(beforeHand),
      );
      final afterStrength = HandEvaluator.evaluate(List<Card>.from(afterHand));
      final beforePerCard = beforeStrength / beforeHandSize;
      final afterPerCard = afterStrength / afterHandSize;
      breakdown['hand_strength_diag'] = (afterPerCard - beforePerCard) * 0.5;
    } else {
      breakdown['hand_strength_diag'] = 0.0;
    }

    if (action is PlayTurnAction) {
      final wasWinning = before.deck.currentWinner == playerId;
      final nowWinning = after.deck.currentWinner == playerId;
      var diag = 0.0;
      if (nowWinning && !wasWinning) {
        final trickValue = after.trickPoints;
        if (trickValue > 0) diag += trickValue * 0.1;
      }
      final playedPoints = pointsForCards(action.cards);
      if (playedPoints > 0 && nowWinning) diag += playedPoints * 0.05;
      breakdown['trick_points_diag'] = diag;
    } else {
      breakdown['trick_points_diag'] = 0.0;
    }

    return _RewardResult(total: total, breakdown: breakdown);
  }

  double _handPlayability(final List<Card> hand) {
    if (hand.isEmpty) return 0;

    final plays = generateLegalTurns(
      DeckState(TichuTurn(TurnType.empty, const []), CardFace.none),
      List<Card>.from(hand),
    );
    if (plays.isEmpty) return 0;

    final sortedPlays = [...plays]
      ..sort((final a, final b) => b.cards.length.compareTo(a.cards.length));

    final remaining = List<Card>.from(hand);
    var groupCount = 0;

    for (final play in sortedPlays) {
      if (remaining.isEmpty) break;

      final playCards = List<Card>.from(play.cards);
      var allPresent = true;
      for (final card in playCards) {
        final idx = remaining.indexWhere((final c) {
          if (card.face == CardFace.phoenix) return c.face == CardFace.phoenix;
          return c.face == card.face && c.color == card.color;
        });
        if (idx < 0) {
          allPresent = false;
          break;
        }
      }

      if (!allPresent) continue;

      for (final card in playCards) {
        final removeIdx = remaining.indexWhere((final c) {
          if (card.face == CardFace.phoenix) return c.face == CardFace.phoenix;
          return c.face == card.face && c.color == card.color;
        });
        if (removeIdx >= 0) remaining.removeAt(removeIdx);
      }
      groupCount++;
    }

    groupCount += remaining.length;
    return hand.length / groupCount;
  }

  double _scoreDelta({
    required final int actorTeam,
    required final ScoreState before,
    required final ScoreState after,
  }) {
    final beforeActor = _teamScore(before, actorTeam);
    final beforeOpponent = _teamScore(before, actorTeam == 0 ? 1 : 0);
    final afterActor = _teamScore(after, actorTeam);
    final afterOpponent = _teamScore(after, actorTeam == 0 ? 1 : 0);
    return (afterActor - beforeActor - (afterOpponent - beforeOpponent))
        .toDouble();
  }

  int _teamScore(final ScoreState scoreState, final int team) {
    if (team == 0) {
      return scoreState.teamOneTotal + scoreState.teamOneRound;
    }
    return scoreState.teamTwoTotal + scoreState.teamTwoRound;
  }

  int _computeLegalTurnCount(
    final GameSnapshot snapshot,
    final String playerId,
  ) {
    if (snapshot.phase != GamePhase.play) return 0;
    final hand = snapshot.hands[playerId] ?? const <Card>[];
    return generateLegalTurns(snapshot.deck, List<Card>.from(hand)).length;
  }

  List<String>? _legalActionKeys(
    final GameSnapshot snapshot,
    final String playerId,
  ) {
    final schupfReceipts = snapshot.schupfReceipts[playerId];
    if (schupfReceipts != null && schupfReceipts.isNotEmpty) {
      return const ['ack_schupf'];
    }

    if (snapshot.currentPlayerId != playerId) return null;

    if (snapshot.phase == GamePhase.grandTichu) {
      return const ['grand_tichu:call', 'grand_tichu:pass'];
    }

    if (snapshot.phase == GamePhase.schupf) return null;
    if (snapshot.phase != GamePhase.play) return null;

    if (snapshot.pendingDragonGiveBy == playerId) {
      final keys = snapshot.pendingDragonGiveTargets
          .map((final id) => 'dragon_give:$id')
          .toList()
        ..sort();
      return keys;
    }

    final hand = List<Card>.from(snapshot.hands[playerId] ?? const <Card>[]);
    final turns = generateLegalTurns(snapshot.deck, hand);
    final keys = <String>{
      for (final turn in turns) encodeRlPlayActionKeyFromCards(turn.cards),
    };

    if (_canPass(snapshot, hand)) keys.add('pass');
    if (snapshot.canCallTichuByPlayer[playerId] ?? false) {
      keys.add('call_tichu');
    }

    final sorted = keys.toList()..sort();
    return sorted;
  }

  bool _canPass(final GameSnapshot snapshot, final List<Card> hand) {
    if (snapshot.deck.turn.type == TurnType.empty ||
        snapshot.deck.turn.type == TurnType.none) {
      return false;
    }
    return !mahJong(snapshot.deck, TichuTurn(TurnType.none, const []), hand);
  }

  Map<String, int> _opponentCounts(
    final GameSnapshot snapshot,
    final String playerId,
  ) {
    final counts = <String, int>{};
    for (final entry in snapshot.hands.entries) {
      if (entry.key == playerId) continue;
      counts[entry.key] = entry.value.length;
    }
    return counts;
  }

  String _actionType(final GameAction action) {
    if (action is PlayTurnAction) return 'play';
    if (action is PassAction) return 'pass';
    if (action is GiveDragonAction) return 'dragon_give';
    if (action is AcknowledgeSchupfAction) return 'ack_schupf';
    if (action is SchupfAction) return 'schupf';
    if (action is CallTichuAction) return 'tichu';
    if (action is CallGrandTichuAction) return 'grand_tichu';
    if (action is GrandTichuDecisionAction) return 'grand_tichu_decision';
    if (action is ConfirmOpponentTurnAction) return 'confirm';
    return 'unknown';
  }

  List<Card> _cardsForAction(final GameAction action) {
    if (action is PlayTurnAction) return action.cards;
    if (action is SchupfAction) {
      return [action.toLeft, action.toPartner, action.toRight];
    }
    return const <Card>[];
  }
}
