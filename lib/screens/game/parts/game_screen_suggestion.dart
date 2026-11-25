part of '../game_screen.dart';

/// Pre-selects the bot's suggested play in the human's hand.
mixin _GameScreenSuggestion on _GameScreenStateBase {
  @override
  Future<void> _maybeApplyAiSuggestion(PlayerSnapshot snapshot) async {
    if (!_isSelfManual || !_aiSuggestionEnabled) {
      _clearAiSuggestionSelection();
      return;
    }
    if (snapshot.phase != GamePhase.play ||
        snapshot.scoreState.roundComplete ||
        snapshot.currentPlayerId != _humanId) {
      _clearAiSuggestionSelection();
      return;
    }
    if (snapshot.pendingDragonGiveBy == _humanId) {
      _clearAiSuggestionSelection();
      return;
    }
    if (_schupfAckPending || snapshot.schupfReceipts.isNotEmpty) {
      _clearAiSuggestionSelection();
      return;
    }

    final isLeading =
        snapshot.deck.turn.type == TurnType.empty ||
        snapshot.deck.turn.type == TurnType.none;
    if (isLeading) {
      _clearAiSuggestionSelection();
      return;
    }

    if (_selectedIndexes.isNotEmpty && !_aiSuggestionSelectionOwned) {
      return;
    }

    final requestId = ++_aiSuggestionRequestId;
    final aiSnapshot = _buildAiSuggestionSnapshot(snapshot);
    final action = await _suggestionAgent.selectTurn(aiSnapshot);
    if (!mounted || requestId != _aiSuggestionRequestId) return;

    if (action is! PlayTurnAction) {
      _clearAiSuggestionSelection();
      return;
    }

    final suggestedIndexes = _playController.cardIndicesInHand(
      _hand,
      action.cards,
    );
    if (suggestedIndexes.isEmpty) {
      _clearAiSuggestionSelection();
      return;
    }

    final suggestedCards = [for (final index in suggestedIndexes) _hand[index]];
    final suggestedTurn = _playController.resolveSelectedTurn(
      snapshot: snapshot,
      selectedCards: suggestedCards,
      hand: _hand,
    );
    if (suggestedTurn == null) {
      _clearAiSuggestionSelection();
      return;
    }

    setState(() {
      _selectedIndexes
        ..clear()
        ..addAll(suggestedIndexes);
      _aiSuggestionSelectionOwned = true;
    });
  }

  @override
  void _clearAiSuggestionSelection() {
    _aiSuggestionRequestId += 1;
    if (!_aiSuggestionSelectionOwned || _selectedIndexes.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _selectedIndexes.clear();
      _aiSuggestionSelectionOwned = false;
    });
  }

  GameSnapshot _buildAiSuggestionSnapshot(PlayerSnapshot snapshot) {
    final hands = <String, List<Card>>{};
    for (final player in snapshot.players) {
      if (player.id == _humanId) {
        hands[player.id] = List<Card>.from(_hand);
        continue;
      }
      final count = snapshot.opponentCardCounts[player.id] ?? 0;
      hands[player.id] = List<Card>.generate(
        count,
        (_) => Card(CardFace.none, CardColor.special),
      );
    }

    return GameSnapshot(
      gameId: snapshot.gameId,
      players: snapshot.players,
      hands: hands,
      deck: snapshot.deck,
      trickPoints: snapshot.trickPoints,
      activeWish: snapshot.activeWish,
      currentPlayerId: snapshot.currentPlayerId,
      consecutivePasses: snapshot.consecutivePasses,
      lastPlayedBy: snapshot.lastPlayedBy,
      lastPlayedTurn: snapshot.lastPlayedTurn,
      lastDragonGiveBy: snapshot.lastDragonGiveBy,
      lastDragonGiveTo: snapshot.lastDragonGiveTo,
      pendingDragonGiveBy: snapshot.pendingDragonGiveBy,
      pendingDragonGiveTargets: snapshot.pendingDragonGiveTargets,
      pendingOpponentPlayerId: snapshot.pendingOpponentPlayerId,
      pendingOpponentCards: snapshot.pendingOpponentCards,
      pendingOpponentPass: snapshot.pendingOpponentPass,
      scoreState: snapshot.scoreState,
      opponentAwaitingConfirmation: snapshot.opponentAwaitingConfirmation,
      phase: snapshot.phase,
      canCallTichuByPlayer: {
        for (final player in snapshot.players)
          player.id: player.id == _humanId && snapshot.canCallTichu,
      },
      hasBombByPlayer: {
        for (final player in snapshot.players)
          player.id: player.id == _humanId && snapshot.hasBombInHand,
      },
      canBombByPlayer: {
        for (final player in snapshot.players)
          player.id: player.id == _humanId && snapshot.canBomb,
      },
      grandTichuDecisions: snapshot.grandTichuDecisions,
      schupfCompletedPlayers: snapshot.schupfCompletedPlayers,
      schupfReceipts: {_humanId: snapshot.schupfReceipts},
    );
  }
}
