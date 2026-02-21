import 'package:meta/meta.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

class GameSnapshot {
  final String gameId;
  final List<GamePlayer> players;
  final Map<String, List<Card>> hands;
  final DeckState deck;
  final int trickPoints;

  /// Backend-owned view of the currently active wish.
  ///
  /// This is the interface field that all backends (local/cloud) must store
  /// and emit for UI consumption.
  final CardFace activeWish;
  final String currentPlayerId;
  final int consecutivePasses;
  final String? lastPlayedBy;
  final TichuTurn? lastPlayedTurn;
  final String? lastDragonGiveBy;
  final String? lastDragonGiveTo;
  final String? pendingDragonGiveBy;
  final List<String> pendingDragonGiveTargets;
  final String? pendingOpponentPlayerId;
  final List<Card> pendingOpponentCards;
  final bool pendingOpponentPass;
  final ScoreState scoreState;
  final bool opponentAwaitingConfirmation;
  final GamePhase phase;
  final Map<String, bool> canCallTichuByPlayer;
  final Map<String, bool> hasBombByPlayer;
  final Map<String, bool> canBombByPlayer;
  final Map<String, bool> grandTichuDecisions;
  final List<String> schupfCompletedPlayers;
  final Map<String, List<SchupfReceipt>> schupfReceipts;

  const GameSnapshot({
    required this.gameId,
    required this.players,
    required this.hands,
    required this.deck,
    required this.trickPoints,
    required this.activeWish,
    required this.currentPlayerId,
    required this.consecutivePasses,
    required this.lastPlayedBy,
    required this.lastPlayedTurn,
    required this.lastDragonGiveBy,
    required this.lastDragonGiveTo,
    required this.pendingDragonGiveBy,
    required this.pendingDragonGiveTargets,
    required this.pendingOpponentPlayerId,
    required this.pendingOpponentCards,
    required this.pendingOpponentPass,
    required this.scoreState,
    required this.opponentAwaitingConfirmation,
    required this.phase,
    this.canCallTichuByPlayer = const {},
    this.hasBombByPlayer = const {},
    this.canBombByPlayer = const {},
    required this.grandTichuDecisions,
    required this.schupfCompletedPlayers,
    required this.schupfReceipts,
  });
}

/// Client-facing snapshot that only exposes the requesting player's hand.
@immutable
class PlayerSnapshot {
  final String gameId;
  final List<GamePlayer> players;
  final List<Card> hand;
  final Map<String, int> opponentCardCounts;
  final DeckState deck;
  final int trickPoints;
  final CardFace activeWish;
  final String currentPlayerId;
  final int consecutivePasses;
  final String? lastPlayedBy;
  final TichuTurn? lastPlayedTurn;
  final String? lastDragonGiveBy;
  final String? lastDragonGiveTo;
  final String? pendingDragonGiveBy;
  final List<String> pendingDragonGiveTargets;
  final String? pendingOpponentPlayerId;
  final List<Card> pendingOpponentCards;
  final bool pendingOpponentPass;
  final ScoreState scoreState;
  final bool opponentAwaitingConfirmation;
  final GamePhase phase;
  final bool canCallTichu;
  final bool hasBombInHand;
  final bool canBomb;
  final Map<String, bool> grandTichuDecisions;
  final List<String> schupfCompletedPlayers;
  final List<SchupfReceipt> schupfReceipts;

  const PlayerSnapshot({
    required this.gameId,
    required this.players,
    required this.hand,
    required this.opponentCardCounts,
    required this.deck,
    required this.trickPoints,
    required this.activeWish,
    required this.currentPlayerId,
    required this.consecutivePasses,
    required this.lastPlayedBy,
    required this.lastPlayedTurn,
    required this.lastDragonGiveBy,
    required this.lastDragonGiveTo,
    required this.pendingDragonGiveBy,
    required this.pendingDragonGiveTargets,
    required this.pendingOpponentPlayerId,
    required this.pendingOpponentCards,
    required this.pendingOpponentPass,
    required this.scoreState,
    required this.opponentAwaitingConfirmation,
    required this.phase,
    this.canCallTichu = false,
    this.hasBombInHand = false,
    this.canBomb = false,
    required this.grandTichuDecisions,
    required this.schupfCompletedPlayers,
    required this.schupfReceipts,
  });
}
