import 'dart:async';
import 'dart:math';

import 'package:tichu/services/game_backend.dart';
import 'package:tichu/view_model/ai/player_agent.dart';
import 'package:tichu/view_model/ai/smart_ai_agent.dart';
import 'package:tichu/view_model/scoring/score_data.dart';
import 'package:tichu/view_model/scoring/score_tracker.dart';
import 'package:tichu/view_model/turn/find_turn.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';
import 'package:tichu/view_model/turn/tichu_rules.dart';
import 'package:tichu/view_model/turn/turn_handler.dart';
import 'package:tichu/view_model/turn/wish_logic.dart';

class LocalGameBackend implements GameBackend {
  final TurnHandler _turnHandler;
  final Random _random;
  final Map<String, _LocalGameState> _games = {};
  final Map<String, PlayerAgent> _aiAgents = {};
  final Set<String> _aiInFlight = {};

  LocalGameBackend({
    TurnHandler? turnHandler,
    Random? random,
    Map<String, PlayerAgent>? aiAgents,
  }) : _turnHandler = turnHandler ?? TurnHandler(),
       _random = random ?? Random() {
    if (aiAgents != null) {
      _aiAgents.addAll(aiAgents);
    }
  }

  @override
  Stream<PlayerSnapshot> watchGame(String gameId, String playerId) {
    final state = _games[gameId];
    if (state == null) {
      throw StateError('Unknown gameId: $gameId');
    }
    return state.controller.stream.map(
      (snapshot) => _toPlayerSnapshot(snapshot, playerId),
    );
  }

  @override
  Future<String> createGame(
    List<GamePlayer> players, {
    int targetScore = 1000,
  }) async {
    if (players.length != 4) {
      throw ArgumentError('Local mode currently supports exactly 4 players.');
    }

    final gameId = DateTime.now().millisecondsSinceEpoch.toString();
    final (hands, reserved) = _dealInitialHands(players);

    final state = _LocalGameState(
      gameId: gameId,
      players: players,
      hands: hands,
      deck: DeckState(TichuTurn(TurnType.empty, []), CardFace.none),
      currentPlayerIndex: 0,
      scoreTracker: LocalScoreTracker(targetScore: targetScore),
      reservedHands: reserved,
      phase: GamePhase.grandTichu,
    );

    _ensureAiAgents(players);

    state.scoreTracker.startNewRound(players);
    state.aiAwaitingConfirmation = false;
    state.grandTichuDecisions.clear();
    state.schupfSelections.clear();
    state.schupfReceipts.clear();

    _games[gameId] = state;
    _emitSnapshot(state);
    _maybeRunAi(state);
    return gameId;
  }

  @override
  Future<void> startNewRound(String gameId) async {
    final state = _games[gameId];
    if (state == null) {
      throw StateError('Unknown gameId: $gameId');
    }
    if (state.scoreTracker.state.gameComplete) {
      throw StateError('Game has ended. Start a new game to play again.');
    }

    final (hands, reserved) = _dealInitialHands(state.players);
    state.hands
      ..clear()
      ..addAll(hands);
    state.deck = DeckState(TichuTurn(TurnType.empty, []), CardFace.none);
    state.currentPlayerIndex = 0;
    state.reservedHands
      ..clear()
      ..addAll(reserved);
    state.phase = GamePhase.grandTichu;
    state.consecutivePasses = 0;
    state.lastPlayedBy = null;
    state.lastPlayedTurn = null;
    state.lastDragonGiveBy = null;
    state.lastDragonGiveTo = null;
    state.pendingDragonGiveBy = null;
    state.pendingDragonGiveTargets.clear();
    state.pendingDragonTrickCards.clear();
    state.pendingAiAction = null;
    state.pendingAiPlayerId = null;
    state.pendingAiCards.clear();
    state.pendingAiPass = false;
    state.currentTrickCards.clear();
    state.finishedPlayers.clear();
    state.aiAwaitingConfirmation = false;
    state.grandTichuDecisions.clear();
    state.schupfSelections.clear();
    state.schupfReceipts.clear();
    state.scoreTracker.startNewRound(state.players);

    _emitSnapshot(state);
    _maybeRunAi(state);
  }

  @override
  Future<void> startGame(String gameId) async {
    final state = _games[gameId];
    if (state == null) {
      throw StateError('Unknown gameId: $gameId');
    }
    state.grandTichuDecisions.clear();
    state.schupfSelections.clear();
    state.schupfReceipts.clear();
    state.lastDragonGiveBy = null;
    state.lastDragonGiveTo = null;
    _emitSnapshot(state);
    _maybeRunAi(state);
  }

  @override
  Future<void> submitAction(String gameId, GameAction action) async {
    final state = _games[gameId];
    if (state == null) {
      throw StateError('Unknown gameId: $gameId');
    }

    if (action is! AcknowledgeSchupfAction &&
        _hasPendingSchupfReceiptsForPlayer(state, action.playerId)) {
      throw StateError('Accept schupf before continuing play.');
    }

    if (state.aiAwaitingConfirmation &&
        action is! ConfirmAiTurnAction &&
        action is! AcknowledgeSchupfAction) {
      throw StateError('Confirm the AI turn before continuing.');
    }

    if (action is ConfirmAiTurnAction) {
      if (!state.aiAwaitingConfirmation || state.pendingAiAction == null) {
        return;
      }
      final pendingAction = state.pendingAiAction!;
      state.aiAwaitingConfirmation = false;
      state.pendingAiAction = null;
      state.pendingAiPlayerId = null;
      state.pendingAiCards.clear();
      state.pendingAiPass = false;
      _applyPendingAction(state, pendingAction);
      _emitSnapshot(state);
      _maybeRunAi(state);
      return;
    }

    if (action is AcknowledgeSchupfAction) {
      _applyAcknowledgeSchupf(state, action);
      _emitSnapshot(state);
      _maybeRunAi(state);
      return;
    }

    if (state.scoreTracker.state.roundComplete) {
      throw StateError('Round has ended. Start a new round to continue.');
    }

    if (state.phase == GamePhase.grandTichu) {
      if (action is CallGrandTichuAction) {
        _applyGrandTichuDecision(
          state,
          GrandTichuDecisionAction(playerId: action.playerId, call: true),
        );
      } else if (action is GrandTichuDecisionAction) {
        _applyGrandTichuDecision(state, action);
      } else {
        throw StateError('Grand tichu decision required before play.');
      }
      _emitSnapshot(state);
      _maybeRunAi(state);
      return;
    }

    if (state.phase == GamePhase.schupf) {
      if (action is! SchupfAction) {
        throw StateError('Schupfen required before play.');
      }
      _applySchupfSelection(state, action);
      _emitSnapshot(state);
      _maybeRunAi(state);
      return;
    }

    if (state.pendingDragonGiveBy != null) {
      if (action is! GiveDragonAction ||
          action.playerId != state.pendingDragonGiveBy) {
        throw StateError('Dragon give required before continuing play.');
      }
      _applyGiveDragonAction(state, action);
      _emitSnapshot(state);
      _maybeRunAi(state);
      return;
    }

    final currentPlayer = state.players[state.currentPlayerIndex];
    if (action.playerId != currentPlayer.id) {
      if (action is PlayTurnAction) {
        final actionTurn = getTurn(List<Card>.from(action.cards));
        final deckType = state.deck.turn.type;
        final canInterrupt =
            actionTurn.type == TurnType.bomb &&
            deckType != TurnType.empty &&
            deckType != TurnType.none;
        if (!canInterrupt) {
          throw StateError('Not this player\'s turn.');
        }
      } else {
        throw StateError('Not this player\'s turn.');
      }
    }

    if (action is PlayTurnAction) {
      _applyPlayAction(state, action);
    } else if (action is PassAction) {
      _applyPassAction(state, action);
    } else if (action is GiveDragonAction) {
      throw StateError('No dragon trick to give.');
    } else if (action is CallTichuAction) {
      state.scoreTracker.recordTichuCall(action.playerId, isGrand: false);
    } else if (action is CallGrandTichuAction) {
      state.scoreTracker.recordTichuCall(action.playerId, isGrand: true);
    } else if (action is AcknowledgeSchupfAction) {
      _applyAcknowledgeSchupf(state, action);
    }

    if (action is PlayTurnAction || action is PassAction) {
      state.aiAwaitingConfirmation =
          state.pendingDragonGiveBy == null &&
          _shouldPauseForAi(state, action.playerId);
    }

    _emitSnapshot(state);
    _maybeRunAi(state);
  }

  @override
  Future<void> disposeGame(String gameId) async {
    final state = _games.remove(gameId);
    await state?.controller.close();
  }

  void _applyPlayAction(_LocalGameState state, PlayTurnAction action) {
    final hand = state.hands[action.playerId] ?? [];
    if (!_handContainsAll(hand, action.cards)) {
      throw StateError('Played cards are not in hand.');
    }

    final updatedDeck = _turnHandler.handleTurn(
      state.deck,
      action.cards,
      action.inputWish,
      hand: hand,
    );
    if (updatedDeck.turn == TichuTurn.InvalidTurn()) {
      throw StateError('Invalid turn.');
    }

    _removeCardsFromHand(hand, action.cards);
    state.deck = updatedDeck;
    state.consecutivePasses = 0;

    final actionIndex = _playerIndexById(state, action.playerId);
    final isInterruptingBomb =
        updatedDeck.turn.type == TurnType.bomb &&
        actionIndex != state.currentPlayerIndex;
    if (isInterruptingBomb) {
      state.currentPlayerIndex = actionIndex;
    }
    state.lastPlayedTurn = updatedDeck.turn;

    final finishedNow = hand.isEmpty;
    if (finishedNow) {
      state.finishedPlayers.add(action.playerId);
      state.scoreTracker.recordPlayerFinished(action.playerId, hand);
    }

    if (state.deck.turn.type == TurnType.dog) {
      state.currentTrickCards.clear();
      state.lastPlayedBy = null;
      state.deck = DeckState(TichuTurn(TurnType.empty, []), state.deck.wish);
      state.currentPlayerIndex = _partnerIndex(state.currentPlayerIndex);
      if (state.finishedPlayers.contains(
        state.players[state.currentPlayerIndex].id,
      )) {
        state.currentPlayerIndex = _nextActiveIndex(
          state,
          state.currentPlayerIndex,
        );
      }
    } else {
      state.currentTrickCards.addAll(action.cards);
      state.lastPlayedBy = action.playerId;
      _advanceToNextPlayer(state);
    }

    if (finishedNow) {
      _finalizeRoundIfComplete(state);
    }
  }

  void _applyPassAction(_LocalGameState state, PassAction action) {
    final hand = state.hands[action.playerId] ?? [];

    if (state.deck.turn.type == TurnType.empty ||
        state.deck.turn.type == TurnType.none) {
      throw StateError('Cannot pass on an empty trick.');
    }

    if (mahJong(state.deck, TichuTurn(TurnType.none, []), hand)) {
      throw StateError('Wish must be fulfilled when possible.');
    }

    state.consecutivePasses += 1;
    final activePlayers = state.players.length - state.finishedPlayers.length;
    final requiredPasses = requiredPassesForTrick(activePlayers);

    if (requiredPasses > 0 && state.consecutivePasses >= requiredPasses) {
      if (state.lastPlayedBy != null) {
        final winnerId = state.lastPlayedBy!;
        final trickCards = List<Card>.from(state.currentTrickCards);
        state.currentTrickCards.clear();
        state.deck = DeckState(TichuTurn(TurnType.empty, []), state.deck.wish);
        state.currentPlayerIndex = _playerIndexById(state, winnerId);
        if (state.finishedPlayers.contains(state.lastPlayedBy!)) {
          state.currentPlayerIndex = _nextActiveIndex(
            state,
            state.currentPlayerIndex,
          );
        }
        _maybeAwardTrick(state, winnerId, trickCards);
        state.consecutivePasses = 0;
        return;
      }
    }

    _advanceToNextPlayer(state);
  }

  void _applyPendingAction(_LocalGameState state, GameAction action) {
    if (state.scoreTracker.state.roundComplete) {
      return;
    }

    if (state.pendingDragonGiveBy != null) {
      throw StateError('Dragon give required before continuing play.');
    }

    final currentPlayer = state.players[state.currentPlayerIndex];
    if (action.playerId != currentPlayer.id) {
      throw StateError('Not this player\'s turn.');
    }

    if (action is PlayTurnAction) {
      _applyPlayAction(state, action);
    } else if (action is PassAction) {
      _applyPassAction(state, action);
    } else if (action is CallTichuAction) {
      state.scoreTracker.recordTichuCall(action.playerId, isGrand: false);
    } else if (action is CallGrandTichuAction) {
      state.scoreTracker.recordTichuCall(action.playerId, isGrand: true);
    } else if (action is GiveDragonAction) {
      throw StateError('No dragon trick to give.');
    }
  }

  void _advanceToNextPlayer(_LocalGameState state) {
    state.currentPlayerIndex = _nextActiveIndex(
      state,
      state.currentPlayerIndex,
    );
  }

  int _nextActiveIndex(_LocalGameState state, int startIndex) {
    final total = state.players.length;
    var next = (startIndex + 1) % total;
    while (state.finishedPlayers.contains(state.players[next].id)) {
      next = (next + 1) % total;
      if (next == startIndex) {
        break;
      }
    }
    return next;
  }

  int _partnerIndex(int index) {
    return (index + 2) % 4;
  }

  int _playerIndexById(_LocalGameState state, String playerId) {
    return state.players.indexWhere((player) => player.id == playerId);
  }

  bool _handContainsAll(List<Card> hand, List<Card> cards) {
    final temp = List<Card>.from(hand);
    for (final card in cards) {
      final index = temp.indexWhere((candidate) {
        if (card.face == CardFace.phoenix) {
          return candidate.face == CardFace.phoenix;
        }
        return candidate.face == card.face && candidate.color == card.color;
      });
      if (index == -1) {
        return false;
      }
      temp.removeAt(index);
    }
    return true;
  }

  void _removeCardsFromHand(List<Card> hand, List<Card> cards) {
    for (final card in cards) {
      final index = hand.indexWhere((candidate) {
        if (card.face == CardFace.phoenix) {
          return candidate.face == CardFace.phoenix;
        }
        return candidate.face == card.face && candidate.color == card.color;
      });
      if (index != -1) {
        hand.removeAt(index);
      }
    }
  }

  void _emitSnapshot(_LocalGameState state) {
    final currentPlayer = state.players[state.currentPlayerIndex];
    state.controller.add(
      GameSnapshot(
        gameId: state.gameId,
        players: state.players,
        hands: state.hands,
        deck: state.deck,
        trickPoints: pointsForCards(state.currentTrickCards),
        activeWish: state.deck.wish,
        currentPlayerId: currentPlayer.id,
        consecutivePasses: state.consecutivePasses,
        lastPlayedBy: state.lastPlayedBy,
        lastPlayedTurn: state.lastPlayedTurn,
        lastDragonGiveBy: state.lastDragonGiveBy,
        lastDragonGiveTo: state.lastDragonGiveTo,
        pendingDragonGiveBy: state.pendingDragonGiveBy,
        pendingDragonGiveTargets: List<String>.from(
          state.pendingDragonGiveTargets,
        ),
        pendingAiPlayerId: state.pendingAiPlayerId,
        pendingAiCards: List<Card>.from(state.pendingAiCards),
        pendingAiPass: state.pendingAiPass,
        scoreState: state.scoreTracker.state,
        aiAwaitingConfirmation: state.aiAwaitingConfirmation,
        phase: state.phase,
        grandTichuDecisions: Map<String, bool>.from(state.grandTichuDecisions),
        schupfCompletedPlayers: List<String>.from(state.schupfSelections.keys),
        schupfReceipts: Map<String, List<SchupfReceipt>>.from(
          state.schupfReceipts,
        ),
      ),
    );
  }

  PlayerSnapshot _toPlayerSnapshot(GameSnapshot snapshot, String playerId) {
    final hand = snapshot.hands[playerId] ?? <Card>[];
    final opponentCardCounts = <String, int>{};
    for (final entry in snapshot.hands.entries) {
      if (entry.key == playerId) continue;
      opponentCardCounts[entry.key] = entry.value.length;
    }

    return PlayerSnapshot(
      gameId: snapshot.gameId,
      players: snapshot.players,
      hand: List<Card>.from(hand),
      opponentCardCounts: opponentCardCounts,
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
      pendingDragonGiveTargets: List<String>.from(
        snapshot.pendingDragonGiveTargets,
      ),
      pendingAiPlayerId: snapshot.pendingAiPlayerId,
      pendingAiCards: List<Card>.from(snapshot.pendingAiCards),
      pendingAiPass: snapshot.pendingAiPass,
      scoreState: snapshot.scoreState,
      aiAwaitingConfirmation: snapshot.aiAwaitingConfirmation,
      phase: snapshot.phase,
      grandTichuDecisions: Map<String, bool>.from(snapshot.grandTichuDecisions),
      schupfCompletedPlayers: List<String>.from(
        snapshot.schupfCompletedPlayers,
      ),
      schupfReceipts: List<SchupfReceipt>.from(
        snapshot.schupfReceipts[playerId] ?? const <SchupfReceipt>[],
      ),
    );
  }

  void _ensureAiAgents(List<GamePlayer> players) {
    for (final player in players) {
      if (player.type == PlayerType.ai && !_aiAgents.containsKey(player.id)) {
        _aiAgents[player.id] = SmartAiAgent(player.id);
      }
    }
  }

  Future<void> _maybeRunAi(_LocalGameState state) async {
    if (state.scoreTracker.state.roundComplete) {
      return;
    }

    if (_hasPendingHumanSchupfReceipts(state)) {
      return;
    }

    if (state.phase == GamePhase.grandTichu) {
      await _resolveGrandTichuForAi(state);
      _emitSnapshot(state);
      if (state.phase != GamePhase.grandTichu) {
        _maybeRunAi(state);
      }
      return;
    }

    if (state.phase == GamePhase.schupf) {
      await _resolveSchupfForAi(state);
      _emitSnapshot(state);
      if (state.phase != GamePhase.schupf) {
        _maybeRunAi(state);
      }
      return;
    }

    if (state.aiAwaitingConfirmation) {
      return;
    }

    if (state.pendingAiAction != null) {
      return;
    }

    if (state.pendingDragonGiveBy != null) {
      final pendingId = state.pendingDragonGiveBy!;
      final pendingPlayer = state.players.firstWhere((p) => p.id == pendingId);
      if (pendingPlayer.type == PlayerType.ai) {
        _autoResolveDragonGive(state, pendingId);
        _emitSnapshot(state);
      }
      return;
    }

    final currentPlayer = state.players[state.currentPlayerIndex];
    final agent = _aiAgents[currentPlayer.id];
    if (agent == null) return;

    final inFlightKey = '${state.gameId}:${currentPlayer.id}';
    if (_aiInFlight.contains(inFlightKey)) return;

    _aiInFlight.add(inFlightKey);
    try {
      final snapshot = _buildSnapshot(state);
      final action = await agent.selectTurn(snapshot);
      state.pendingAiAction = action;
      state.pendingAiPlayerId = currentPlayer.id;
      state.pendingAiCards
        ..clear()
        ..addAll(action is PlayTurnAction ? action.cards : const <Card>[]);
      state.pendingAiPass = action is PassAction;
      state.aiAwaitingConfirmation = true;
      _emitSnapshot(state);
    } finally {
      _aiInFlight.remove(inFlightKey);
    }
  }

  void _applyGrandTichuDecision(
    _LocalGameState state,
    GrandTichuDecisionAction action,
  ) {
    if (state.grandTichuDecisions.containsKey(action.playerId)) {
      return;
    }

    state.grandTichuDecisions[action.playerId] = action.call;
    if (action.call) {
      state.scoreTracker.recordTichuCall(action.playerId, isGrand: true);
    }

    _maybeFinalizeGrandTichu(state);
  }

  Future<void> _resolveGrandTichuForAi(_LocalGameState state) async {
    final snapshot = _buildSnapshot(state);
    for (final player in state.players) {
      if (player.type != PlayerType.ai) continue;
      if (state.grandTichuDecisions.containsKey(player.id)) continue;
      final agent = _aiAgents[player.id];
      if (agent == null) continue;
      final shouldCall = await agent.shouldCallGrandTichu(snapshot);
      _applyGrandTichuDecision(
        state,
        GrandTichuDecisionAction(playerId: player.id, call: shouldCall),
      );
    }
  }

  void _maybeFinalizeGrandTichu(_LocalGameState state) {
    if (state.grandTichuDecisions.length < state.players.length) {
      return;
    }

    for (final player in state.players) {
      final extras = state.reservedHands[player.id];
      if (extras == null || extras.isEmpty) continue;
      final hand = state.hands[player.id];
      if (hand != null) {
        hand.addAll(extras);
      }
    }
    state.reservedHands.clear();
    state.phase = GamePhase.schupf;
    state.schupfSelections.clear();
  }

  void _applySchupfSelection(_LocalGameState state, SchupfAction action) {
    if (state.schupfSelections.containsKey(action.playerId)) {
      return;
    }

    final hand = state.hands[action.playerId] ?? <Card>[];
    final selected = [action.toLeft, action.toPartner, action.toRight];
    if (!_handContainsAll(hand, selected)) {
      throw StateError('Schupf cards are not in hand.');
    }

    state.schupfSelections[action.playerId] = action;
    _maybeFinalizeSchupf(state);
  }

  void _applyAcknowledgeSchupf(
    _LocalGameState state,
    AcknowledgeSchupfAction action,
  ) {
    state.schupfReceipts.remove(action.playerId);
  }

  Future<void> _resolveSchupfForAi(_LocalGameState state) async {
    final snapshot = _buildSnapshot(state);
    for (final player in state.players) {
      if (player.type != PlayerType.ai) continue;
      if (state.schupfSelections.containsKey(player.id)) continue;
      final agent = _aiAgents[player.id];
      if (agent == null) continue;
      final selection = await agent.selectSchupfCards(snapshot);
      _applySchupfSelection(state, selection);
    }
  }

  void _maybeFinalizeSchupf(_LocalGameState state) {
    if (state.schupfSelections.length < state.players.length) {
      return;
    }

    final seatToPlayer = {
      for (final player in state.players) player.seat: player.id,
    };
    final idToSeat = {
      for (final player in state.players) player.id: player.seat,
    };
    final additions = <String, List<Card>>{};
    final receipts = <String, List<SchupfReceipt>>{};

    for (final entry in state.schupfSelections.entries) {
      final sourceId = entry.key;
      final action = entry.value;
      final sourcePlayer = state.players.firstWhere((p) => p.id == sourceId);
      final leftId = seatToPlayer[(sourcePlayer.seat + 1) % 4]!;
      final partnerId = seatToPlayer[(sourcePlayer.seat + 2) % 4]!;
      final rightId = seatToPlayer[(sourcePlayer.seat + 3) % 4]!;

      final sourceHand = state.hands[sourceId] ?? <Card>[];
      _removeCardsFromHand(sourceHand, [
        action.toLeft,
        action.toPartner,
        action.toRight,
      ]);

      additions.putIfAbsent(leftId, () => <Card>[]).add(action.toLeft);
      additions.putIfAbsent(partnerId, () => <Card>[]).add(action.toPartner);
      additions.putIfAbsent(rightId, () => <Card>[]).add(action.toRight);

      _addSchupfReceipt(
        receipts,
        recipientId: leftId,
        fromPlayerId: sourceId,
        direction: _schupfDirectionForRecipient(idToSeat, sourceId, leftId),
        card: action.toLeft,
      );
      _addSchupfReceipt(
        receipts,
        recipientId: partnerId,
        fromPlayerId: sourceId,
        direction: _schupfDirectionForRecipient(idToSeat, sourceId, partnerId),
        card: action.toPartner,
      );
      _addSchupfReceipt(
        receipts,
        recipientId: rightId,
        fromPlayerId: sourceId,
        direction: _schupfDirectionForRecipient(idToSeat, sourceId, rightId),
        card: action.toRight,
      );
    }

    for (final entry in additions.entries) {
      final hand = state.hands[entry.key];
      hand?.addAll(entry.value);
    }

    state.schupfSelections.clear();
    state.schupfReceipts
      ..clear()
      ..addAll(receipts);
    state.phase = GamePhase.play;
    state.deck = DeckState(TichuTurn(TurnType.empty, []), state.deck.wish);
    state.consecutivePasses = 0;
    state.lastPlayedBy = null;
    state.lastPlayedTurn = null;
    state.currentPlayerIndex = _startingPlayerIndex(state);
  }

  SchupfDirection _schupfDirectionForRecipient(
    Map<String, int> idToSeat,
    String fromPlayerId,
    String recipientId,
  ) {
    final fromSeat = idToSeat[fromPlayerId] ?? 0;
    final recipientSeat = idToSeat[recipientId] ?? 0;
    if (fromSeat == (recipientSeat + 1) % 4) {
      return SchupfDirection.left;
    }
    if (fromSeat == (recipientSeat + 2) % 4) {
      return SchupfDirection.partner;
    }
    return SchupfDirection.right;
  }

  void _addSchupfReceipt(
    Map<String, List<SchupfReceipt>> receipts, {
    required String recipientId,
    required String fromPlayerId,
    required SchupfDirection direction,
    required Card card,
  }) {
    receipts
        .putIfAbsent(recipientId, () => <SchupfReceipt>[])
        .add(
          SchupfReceipt(
            card: card,
            fromPlayerId: fromPlayerId,
            direction: direction,
          ),
        );
  }

  int _startingPlayerIndex(_LocalGameState state) {
    for (var i = 0; i < state.players.length; i++) {
      final playerId = state.players[i].id;
      final hand = state.hands[playerId] ?? const <Card>[];
      if (hand.any((card) => card.face == CardFace.mahJong)) {
        return i;
      }
    }
    return 0;
  }

  bool _hasPendingSchupfReceiptsForPlayer(
    _LocalGameState state,
    String playerId,
  ) {
    final player = state.players.firstWhere(
      (p) => p.id == playerId,
      orElse: () => state.players.first,
    );
    if (player.type != PlayerType.human) return false;
    final receipts = state.schupfReceipts[playerId];
    return receipts != null && receipts.isNotEmpty;
  }

  bool _hasPendingHumanSchupfReceipts(_LocalGameState state) {
    for (final player in state.players) {
      if (player.type != PlayerType.human) continue;
      final receipts = state.schupfReceipts[player.id];
      if (receipts != null && receipts.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  void _finalizeRoundIfComplete(_LocalGameState state) {
    if (state.scoreTracker.state.roundComplete) return;

    if (state.finishedPlayers.length >= state.players.length - 1) {
      if (state.lastPlayedBy != null && state.currentTrickCards.isNotEmpty) {
        final winnerId = state.lastPlayedBy!;
        final trickCards = List<Card>.from(state.currentTrickCards);
        state.currentTrickCards.clear();
        _maybeAwardTrick(state, winnerId, trickCards);
      }
      if (state.pendingDragonGiveBy == null) {
        state.currentTrickCards.clear();
        state.scoreTracker.finalizeRound(state.hands);
        state.aiAwaitingConfirmation = false;
      }
    }
  }

  GameSnapshot _buildSnapshot(_LocalGameState state) {
    final currentPlayer = state.players[state.currentPlayerIndex];
    return GameSnapshot(
      gameId: state.gameId,
      players: state.players,
      hands: state.hands,
      deck: state.deck,
      trickPoints: pointsForCards(state.currentTrickCards),
      activeWish: state.deck.wish,
      currentPlayerId: currentPlayer.id,
      consecutivePasses: state.consecutivePasses,
      lastPlayedBy: state.lastPlayedBy,
      lastPlayedTurn: state.lastPlayedTurn,
      lastDragonGiveBy: state.lastDragonGiveBy,
      lastDragonGiveTo: state.lastDragonGiveTo,
      pendingDragonGiveBy: state.pendingDragonGiveBy,
      pendingDragonGiveTargets: List<String>.from(
        state.pendingDragonGiveTargets,
      ),
      pendingAiPlayerId: state.pendingAiPlayerId,
      pendingAiCards: List<Card>.from(state.pendingAiCards),
      pendingAiPass: state.pendingAiPass,
      scoreState: state.scoreTracker.state,
      aiAwaitingConfirmation: state.aiAwaitingConfirmation,
      phase: state.phase,
      grandTichuDecisions: Map<String, bool>.from(state.grandTichuDecisions),
      schupfCompletedPlayers: List<String>.from(state.schupfSelections.keys),
      schupfReceipts: Map<String, List<SchupfReceipt>>.from(
        state.schupfReceipts,
      ),
    );
  }

  bool _maybeAwardTrick(
    _LocalGameState state,
    String winnerId,
    List<Card> trickCards,
  ) {
    if (!_dragonWonTrick(state)) {
      state.scoreTracker.recordTrick(winnerId, trickCards);
      state.lastDragonGiveBy = null;
      state.lastDragonGiveTo = null;
      return true;
    }

    final opponentIds = _opponentIds(state, winnerId);
    if (opponentIds.isEmpty) {
      state.scoreTracker.recordTrick(winnerId, trickCards);
      state.lastDragonGiveBy = null;
      state.lastDragonGiveTo = null;
      return true;
    }

    final winnerPlayer = state.players.firstWhere((p) => p.id == winnerId);
    if (winnerPlayer.type == PlayerType.ai) {
      _autoResolveDragonGive(state, winnerId, trickCards: trickCards);
      return true;
    }

    state.pendingDragonGiveBy = winnerId;
    state.pendingDragonGiveTargets
      ..clear()
      ..addAll(opponentIds);
    state.pendingDragonTrickCards
      ..clear()
      ..addAll(trickCards);
    return false;
  }

  void _autoResolveDragonGive(
    _LocalGameState state,
    String winnerId, {
    List<Card>? trickCards,
  }) {
    final cards = trickCards ?? List<Card>.from(state.pendingDragonTrickCards);
    if (cards.isEmpty) {
      return;
    }

    final opponentIds = _opponentIds(state, winnerId);
    if (opponentIds.isEmpty) {
      state.scoreTracker.recordTrick(winnerId, cards);
      state.lastDragonGiveBy = null;
      state.lastDragonGiveTo = null;
      return;
    }

    final agent = _aiAgents[winnerId];
    final snapshot = _buildSnapshot(state);
    final seat = agent?.selectDragonGive(snapshot);
    final target = state.players.firstWhere(
      (player) => player.seat == seat,
      orElse: () =>
          state.players.firstWhere((player) => opponentIds.contains(player.id)),
    );
    final targetId = opponentIds.contains(target.id)
        ? target.id
        : opponentIds.first;

    state.scoreTracker.recordTrick(targetId, cards);
    state.lastDragonGiveBy = winnerId;
    state.lastDragonGiveTo = targetId;
    state.pendingDragonGiveBy = null;
    state.pendingDragonGiveTargets.clear();
    state.pendingDragonTrickCards.clear();
  }

  void _applyGiveDragonAction(_LocalGameState state, GiveDragonAction action) {
    if (state.pendingDragonGiveBy == null) {
      throw StateError('No dragon trick to give.');
    }
    if (!state.pendingDragonGiveTargets.contains(action.targetPlayerId)) {
      throw StateError('Dragon trick must be given to an opponent.');
    }

    state.scoreTracker.recordTrick(
      action.targetPlayerId,
      List<Card>.from(state.pendingDragonTrickCards),
    );
    state.lastDragonGiveBy = action.playerId;
    state.lastDragonGiveTo = action.targetPlayerId;
    state.pendingDragonGiveBy = null;
    state.pendingDragonGiveTargets.clear();
    state.pendingDragonTrickCards.clear();

    _finalizeRoundIfComplete(state);
  }

  bool _dragonWonTrick(_LocalGameState state) {
    final lastTurn = state.lastPlayedTurn;
    if (lastTurn == null) return false;
    if (lastTurn.type != TurnType.single) return false;
    return lastTurn.cards.any((card) => card.face == CardFace.dragon);
  }

  List<String> _opponentIds(_LocalGameState state, String playerId) {
    final player = state.players.firstWhere((p) => p.id == playerId);
    return state.players
        .where((p) => p.id != playerId && (p.seat % 2 != player.seat % 2))
        .map((p) => p.id)
        .toList();
  }

  bool _shouldPauseForAi(_LocalGameState state, String actorId) {
    final actor = state.players.firstWhere((player) => player.id == actorId);
    if (actor.type != PlayerType.ai) return false;
    if (state.scoreTracker.state.roundComplete) return false;
    if (state.scoreTracker.state.gameComplete) return false;
    final anyHumanOut = state.players
        .where((player) => player.type == PlayerType.human)
        .any((player) => (state.hands[player.id] ?? const []).isEmpty);
    if (anyHumanOut) return false;
    final nextPlayer = state.players[state.currentPlayerIndex];
    return nextPlayer.type == PlayerType.ai;
  }

  (Map<String, List<Card>> hands, Map<String, List<Card>> reserved)
  _dealInitialHands(List<GamePlayer> players) {
    final deckCards = cardIdentifiers.values.toList();
    deckCards.shuffle(_random);

    final hands = <String, List<Card>>{};
    final reserved = <String, List<Card>>{};
    for (var i = 0; i < players.length; i++) {
      final start = i * 14;
      hands[players[i].id] = deckCards.sublist(start, start + 8).toList();
      reserved[players[i].id] = deckCards
          .sublist(start + 8, start + 14)
          .toList();
    }

    return (hands, reserved);
  }
}

class _LocalGameState {
  final String gameId;
  final List<GamePlayer> players;
  final Map<String, List<Card>> hands;
  final Map<String, List<Card>> reservedHands;
  final StreamController<GameSnapshot> controller;
  final LocalScoreTracker scoreTracker;

  DeckState deck;
  int currentPlayerIndex;
  int consecutivePasses = 0;
  String? lastPlayedBy;
  TichuTurn? lastPlayedTurn;
  String? lastDragonGiveBy;
  String? lastDragonGiveTo;
  String? pendingDragonGiveBy;
  final List<String> pendingDragonGiveTargets = [];
  final List<Card> pendingDragonTrickCards = [];
  GameAction? pendingAiAction;
  String? pendingAiPlayerId;
  final List<Card> pendingAiCards = [];
  bool pendingAiPass = false;
  bool aiAwaitingConfirmation = false;
  final List<Card> currentTrickCards = [];
  final Set<String> finishedPlayers = {};
  GamePhase phase;
  final Map<String, bool> grandTichuDecisions = {};
  final Map<String, SchupfAction> schupfSelections = {};
  final Map<String, List<SchupfReceipt>> schupfReceipts = {};

  _LocalGameState({
    required this.gameId,
    required this.players,
    required this.hands,
    required this.deck,
    required this.currentPlayerIndex,
    required this.scoreTracker,
    required this.reservedHands,
    required this.phase,
  }) : controller = StreamController<GameSnapshot>.broadcast();
}
