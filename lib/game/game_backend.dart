import 'package:meta/meta.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

enum PlayerType { human, automated }

enum GamePhase { grandTichu, schupf, play }

enum SchupfDirection { left, partner, right }

class SchupfReceipt {
  final Card card;
  final String fromPlayerId;
  final SchupfDirection direction;

  const SchupfReceipt({
    required this.card,
    required this.fromPlayerId,
    required this.direction,
  });
}

class GamePlayer {
  final String id;
  final String name;
  final int seat;
  final PlayerType type;

  const GamePlayer({
    required this.id,
    required this.name,
    required this.seat,
    required this.type,
  });
}

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
    required this.grandTichuDecisions,
    required this.schupfCompletedPlayers,
    required this.schupfReceipts,
  });
}

abstract class GameAction {
  final String playerId;

  const GameAction({required this.playerId});
}

class PlayTurnAction extends GameAction {
  final List<Card> cards;
  final CardFace inputWish;

  const PlayTurnAction({
    required super.playerId,
    required this.cards,
    this.inputWish = CardFace.none,
  });
}

class PassAction extends GameAction {
  const PassAction({required super.playerId});
}

class GiveDragonAction extends GameAction {
  final String targetPlayerId;

  const GiveDragonAction({
    required super.playerId,
    required this.targetPlayerId,
  });
}

class ConfirmOpponentTurnAction extends GameAction {
  const ConfirmOpponentTurnAction({required super.playerId});
}

class CallTichuAction extends GameAction {
  const CallTichuAction({required super.playerId});
}

class CallGrandTichuAction extends GameAction {
  const CallGrandTichuAction({required super.playerId});
}

class GrandTichuDecisionAction extends GameAction {
  final bool call;

  const GrandTichuDecisionAction({required super.playerId, required this.call});
}

class SchupfAction extends GameAction {
  final Card toLeft;
  final Card toPartner;
  final Card toRight;

  const SchupfAction({
    required super.playerId,
    required this.toLeft,
    required this.toPartner,
    required this.toRight,
  });
}

class AcknowledgeSchupfAction extends GameAction {
  const AcknowledgeSchupfAction({required super.playerId});
}

abstract class GameBackend {
  Stream<PlayerSnapshot> watchGame(String gameId, String playerId);

  Future<String> createGame(List<GamePlayer> players, {int targetScore = 1000});

  Future<void> startGame(String gameId);

  Future<void> startNewRound(String gameId);

  Future<void> submitAction(String gameId, GameAction action);

  Future<void> disposeGame(String gameId);
}

// Shared card identifiers for building full decks.
final Map<int, Card> cardIdentifiers = {
  0: Card(CardFace.ace, CardColor.green),
  1: Card(CardFace.two, CardColor.green),
  2: Card(CardFace.three, CardColor.green),
  3: Card(CardFace.four, CardColor.green),
  4: Card(CardFace.five, CardColor.green),
  5: Card(CardFace.six, CardColor.green),
  6: Card(CardFace.seven, CardColor.green),
  7: Card(CardFace.eight, CardColor.green),
  8: Card(CardFace.nine, CardColor.green),
  9: Card(CardFace.ten, CardColor.green),
  10: Card(CardFace.jack, CardColor.green),
  11: Card(CardFace.queen, CardColor.green),
  12: Card(CardFace.king, CardColor.green),
  13: Card(CardFace.ace, CardColor.blue),
  14: Card(CardFace.two, CardColor.blue),
  15: Card(CardFace.three, CardColor.blue),
  16: Card(CardFace.four, CardColor.blue),
  17: Card(CardFace.five, CardColor.blue),
  18: Card(CardFace.six, CardColor.blue),
  19: Card(CardFace.seven, CardColor.blue),
  20: Card(CardFace.eight, CardColor.blue),
  21: Card(CardFace.nine, CardColor.blue),
  22: Card(CardFace.ten, CardColor.blue),
  23: Card(CardFace.jack, CardColor.blue),
  24: Card(CardFace.queen, CardColor.blue),
  25: Card(CardFace.king, CardColor.blue),
  26: Card(CardFace.ace, CardColor.black),
  27: Card(CardFace.two, CardColor.black),
  28: Card(CardFace.three, CardColor.black),
  29: Card(CardFace.four, CardColor.black),
  30: Card(CardFace.five, CardColor.black),
  31: Card(CardFace.six, CardColor.black),
  32: Card(CardFace.seven, CardColor.black),
  33: Card(CardFace.eight, CardColor.black),
  34: Card(CardFace.nine, CardColor.black),
  35: Card(CardFace.ten, CardColor.black),
  36: Card(CardFace.jack, CardColor.black),
  37: Card(CardFace.queen, CardColor.black),
  38: Card(CardFace.king, CardColor.black),
  39: Card(CardFace.ace, CardColor.red),
  40: Card(CardFace.two, CardColor.red),
  41: Card(CardFace.three, CardColor.red),
  42: Card(CardFace.four, CardColor.red),
  43: Card(CardFace.five, CardColor.red),
  44: Card(CardFace.six, CardColor.red),
  45: Card(CardFace.seven, CardColor.red),
  46: Card(CardFace.eight, CardColor.red),
  47: Card(CardFace.nine, CardColor.red),
  48: Card(CardFace.ten, CardColor.red),
  49: Card(CardFace.jack, CardColor.red),
  50: Card(CardFace.queen, CardColor.red),
  51: Card(CardFace.king, CardColor.red),
  52: Card(CardFace.mahJong, CardColor.special),
  53: Card(CardFace.phoenix, CardColor.special),
  54: Card(CardFace.dog, CardColor.special),
  55: Card(CardFace.dragon, CardColor.special),
};
