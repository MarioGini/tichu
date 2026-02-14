import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/engine_state.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/turn_handler.dart';
import 'package:tichu/game/turn/utils/engine/hand_utils.dart';
import 'package:tichu/game/turn/utils/engine/turn_order.dart';
import 'package:tichu/game/turn/wish_logic.dart';

void applyPlayAction(
  GameEngineState state,
  PlayTurnAction action,
  TurnHandler turnHandler,
) {
  final hand = state.hands[action.playerId] ?? [];
  if (!handContainsAll(hand, action.cards)) {
    throw StateError('Played cards are not in hand.');
  }

  final updatedDeck = turnHandler.handleTurn(
    state.deck,
    action.cards,
    action.inputWish,
    hand: hand,
  );
  if (updatedDeck.turn == TichuTurn.InvalidTurn()) {
    throw StateError('Invalid turn.');
  }

  removeCardsFromHand(hand, action.cards);
  state.playersWhoPlayedCardsThisRound.add(action.playerId);
  state.deck = updatedDeck;
  state.consecutivePasses = 0;

  final actionIndex = playerIndexById(state, action.playerId);
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
    state.currentPlayerIndex = partnerIndex(state.currentPlayerIndex);
    if (state.finishedPlayers.contains(
      state.players[state.currentPlayerIndex].id,
    )) {
      state.currentPlayerIndex = nextActiveIndex(
        state,
        state.currentPlayerIndex,
      );
    }
  } else {
    state.currentTrickCards.addAll(action.cards);
    state.lastPlayedBy = action.playerId;
    advanceToNextPlayer(state);
  }

  if (finishedNow) {
    finalizeRoundIfComplete(state);
  }
}

void applyPassAction(GameEngineState state, PassAction action) {
  final hand = state.hands[action.playerId] ?? [];

  if (state.deck.turn.type == TurnType.empty ||
      state.deck.turn.type == TurnType.none) {
    throw StateError('Cannot pass on an empty trick.');
  }

  if (mahJong(state.deck, TichuTurn(TurnType.none, []), hand)) {
    throw StateError('Wish must be fulfilled when possible.');
  }

  state.consecutivePasses += 1;
  advanceToNextPlayer(state);

  final winnerId = state.lastPlayedBy;
  if (winnerId == null) {
    return;
  }

  final leadReturnIndex = _leadReturnIndex(state, winnerId);
  if (state.currentPlayerIndex != leadReturnIndex) {
    return;
  }

  final trickCards = List<Card>.from(state.currentTrickCards);
  state.currentTrickCards.clear();
  state.deck = DeckState(TichuTurn(TurnType.empty, []), state.deck.wish);
  maybeAwardTrick(state, winnerId, trickCards);
  state.consecutivePasses = 0;
}

int _leadReturnIndex(GameEngineState state, String winnerId) {
  final winnerIndex = playerIndexById(state, winnerId);
  if (winnerIndex < 0) {
    return state.currentPlayerIndex;
  }
  if (!state.finishedPlayers.contains(winnerId)) {
    return winnerIndex;
  }
  return nextActiveIndex(state, winnerIndex);
}

void finalizeRoundIfComplete(GameEngineState state) {
  if (state.scoreTracker.state.roundComplete) return;

  if (state.finishedPlayers.length >= state.players.length - 1) {
    if (state.lastPlayedBy != null && state.currentTrickCards.isNotEmpty) {
      final winnerId = state.lastPlayedBy!;
      final trickCards = List<Card>.from(state.currentTrickCards);
      state.currentTrickCards.clear();
      maybeAwardTrick(state, winnerId, trickCards);
    }
    if (state.pendingDragonGiveBy == null) {
      state.currentTrickCards.clear();
      state.scoreTracker.finalizeRound(state.hands);
    }
  }
}

bool maybeAwardTrick(
  GameEngineState state,
  String winnerId,
  List<Card> trickCards,
) {
  if (!dragonWonTrick(state)) {
    state.scoreTracker.recordTrick(winnerId, trickCards);
    state.lastDragonGiveBy = null;
    state.lastDragonGiveTo = null;
    return true;
  }

  final opponentPlayerIds = opponentIdsForPlayer(state, winnerId);
  if (opponentPlayerIds.isEmpty) {
    state.scoreTracker.recordTrick(winnerId, trickCards);
    state.lastDragonGiveBy = null;
    state.lastDragonGiveTo = null;
    return true;
  }

  state.pendingDragonGiveBy = winnerId;
  state.pendingDragonGiveTargets
    ..clear()
    ..addAll(opponentPlayerIds);
  state.pendingDragonTrickCards
    ..clear()
    ..addAll(trickCards);
  return false;
}

void applyGiveDragonAction(GameEngineState state, GiveDragonAction action) {
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

  finalizeRoundIfComplete(state);
}

bool dragonWonTrick(GameEngineState state) {
  final lastTurn = state.lastPlayedTurn;
  if (lastTurn == null) return false;
  if (lastTurn.type != TurnType.single) return false;
  return lastTurn.cards.any((card) => card.face == CardFace.dragon);
}
