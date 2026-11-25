import 'package:tichu/game/engine_state.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/round_log.dart';
import 'package:tichu/game/scoring/score_data.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/bomb_utils.dart';

/// Full-information snapshot of [state] (all hands).
GameSnapshot buildGameSnapshot(
  GameEngineState state, {
  String? pendingOpponentPlayerId,
  List<Card>? pendingOpponentCards,
  bool pendingOpponentPass = false,
  bool opponentAwaitingConfirmation = false,
}) {
  final currentPlayer = state.players[state.currentPlayerIndex];
  final hasBombByPlayer = {
    for (final player in state.players)
      player.id: hasBombInHand(state.hands[player.id] ?? const <Card>[]),
  };
  final snapshotHands = {
    for (final entry in state.hands.entries)
      entry.key: List<Card>.from(entry.value),
  };
  final snapshotDeck =
      DeckState(
          TichuTurn(
            state.deck.turn.type,
            List<Card>.from(state.deck.turn.cards),
          ),
          state.deck.wish,
        )
        // The engine never sets deck.currentWinner itself; the player who
        // played the current top combination is the trick's winner so far.
        ..currentWinner = state.deck.currentWinner.isNotEmpty
            ? state.deck.currentWinner
            : (_trickActive(state.deck) ? state.lastPlayedBy ?? '' : '')
        ..cardStack = List<Card>.from(state.deck.cardStack);

  return GameSnapshot(
    gameId: state.gameId,
    players: List<GamePlayer>.from(state.players),
    hands: snapshotHands,
    deck: snapshotDeck,
    trickPoints: pointsForCards(state.currentTrickCards),
    activeWish: state.deck.wish,
    currentPlayerId: currentPlayer.id,
    consecutivePasses: state.consecutivePasses,
    lastPlayedBy: state.lastPlayedBy,
    lastPlayedTurn: state.lastPlayedTurn,
    lastDragonGiveBy: state.lastDragonGiveBy,
    lastDragonGiveTo: state.lastDragonGiveTo,
    pendingDragonGiveBy: state.pendingDragonGiveBy,
    pendingDragonGiveTargets: List<String>.from(state.pendingDragonGiveTargets),
    pendingOpponentPlayerId: pendingOpponentPlayerId,
    pendingOpponentCards: List<Card>.from(
      pendingOpponentCards ?? const <Card>[],
    ),
    pendingOpponentPass: pendingOpponentPass,
    scoreState: state.scoreTracker.state,
    opponentAwaitingConfirmation: opponentAwaitingConfirmation,
    phase: state.phase,
    canCallTichuByPlayer: {
      for (final player in state.players)
        player.id: canPlayerCallTichu(state, player.id),
    },
    hasBombByPlayer: hasBombByPlayer,
    canBombByPlayer: {
      for (final player in state.players)
        player.id:
            hasBombByPlayer[player.id]! && _canPlayerBombNow(state, player.id),
    },
    grandTichuDecisions: Map<String, bool>.from(state.grandTichuDecisions),
    schupfCompletedPlayers: List<String>.from(state.schupfSelections.keys),
    schupfSelections: Map<String, SchupfAction>.from(
      state.schupfSelections.isNotEmpty
          ? state.schupfSelections
          : state.completedSchupfSelections,
    ),
    schupfReceipts: Map<String, List<SchupfReceipt>>.from(state.schupfReceipts),
    roundLog: List<RoundLogEntry>.unmodifiable(state.roundLog),
  );
}

/// [snapshot] as seen by [playerId]: own hand, card counts for the others.
PlayerSnapshot buildPlayerView(GameSnapshot snapshot, String playerId) {
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
    pendingOpponentPlayerId: snapshot.pendingOpponentPlayerId,
    pendingOpponentCards: List<Card>.from(snapshot.pendingOpponentCards),
    pendingOpponentPass: snapshot.pendingOpponentPass,
    scoreState: snapshot.scoreState,
    opponentAwaitingConfirmation: snapshot.opponentAwaitingConfirmation,
    phase: snapshot.phase,
    canCallTichu: snapshot.canCallTichuByPlayer[playerId] ?? false,
    hasBombInHand: snapshot.hasBombByPlayer[playerId] ?? false,
    canBomb: snapshot.canBombByPlayer[playerId] ?? false,
    grandTichuDecisions: Map<String, bool>.from(snapshot.grandTichuDecisions),
    schupfCompletedPlayers: List<String>.from(snapshot.schupfCompletedPlayers),
    schupfReceipts: List<SchupfReceipt>.from(
      snapshot.schupfReceipts[playerId] ?? const <SchupfReceipt>[],
    ),
  );
}

/// Tichu is callable until the player has played their first card.
bool canPlayerCallTichu(GameEngineState state, String playerId) {
  if (state.phase != GamePhase.play &&
      state.phase != GamePhase.schupf &&
      state.phase != GamePhase.grandTichu) {
    return false;
  }

  final playerCall = state.scoreTracker.state.tichuCalls[playerId];
  if (playerCall != null && playerCall != TichuCall.none) {
    return false;
  }

  return !state.playersWhoPlayedCardsThisRound.contains(playerId);
}

/// Whether a player who holds a bomb may play it now.
bool _canPlayerBombNow(GameEngineState state, String playerId) {
  if (state.phase != GamePhase.play) return false;
  if (state.pendingDragonGiveBy == playerId) return false;

  final currentPlayer = state.players[state.currentPlayerIndex].id;
  final deckType = state.deck.turn.type;
  if (currentPlayer != playerId &&
      (deckType == TurnType.empty || deckType == TurnType.none)) {
    return false;
  }

  return true;
}

bool _trickActive(DeckState deck) =>
    deck.turn.type != TurnType.empty && deck.turn.type != TurnType.none;
