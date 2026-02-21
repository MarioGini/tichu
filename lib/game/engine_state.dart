import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

class GameEngineState {
  final String gameId;
  final List<GamePlayer> players;
  final Map<String, List<Card>> hands;
  final Map<String, List<Card>> reservedHands;
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
  final List<Card> currentTrickCards = [];
  final Set<String> finishedPlayers = {};
  final Set<String> playersWhoPlayedCardsThisRound = {};
  GamePhase phase;
  final Map<String, bool> grandTichuDecisions = {};
  final Map<String, SchupfAction> schupfSelections = {};
  final Map<String, List<SchupfReceipt>> schupfReceipts = {};
  final Map<String, List<Card>> schupfPendingAdditions = {};

  GameEngineState({
    required this.gameId,
    required this.players,
    required this.hands,
    required this.deck,
    required this.currentPlayerIndex,
    required this.scoreTracker,
    required this.reservedHands,
    required this.phase,
  });
}
