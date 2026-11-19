import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/round_log.dart';
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

  /// Every play and pass of the current round, in order (public record).
  final List<RoundLogEntry> roundLog = [];

  /// Players who declined an out-of-turn bomb, with the [bombWindow] they
  /// declined in. A window lasts until the next play or pass.
  final Map<String, String> bombDeclines = {};

  /// Identifies the moment between two plays/passes in which players may
  /// bomb out of turn.
  String get bombWindow =>
      '${scoreTracker.state.roundNumber}:${roundLog.length}';
  GamePhase phase;
  final Map<String, bool> grandTichuDecisions = {};
  final Map<String, SchupfAction> schupfSelections = {};

  /// This round's exchange after it completed (`schupfSelections` is
  /// cleared when the cards are swapped). Cleared at round start.
  final Map<String, SchupfAction> completedSchupfSelections = {};
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

  /// Independent deep copy of the whole state (cards are immutable values
  /// and shared; every collection is copied).
  GameEngineState copy() {
    final c =
        GameEngineState(
            gameId: gameId,
            players: players,
            hands: {
              for (final e in hands.entries) e.key: List<Card>.from(e.value),
            },
            deck: DeckState(deck.turn, deck.wish)
              ..currentWinner = deck.currentWinner
              ..cardStack = List<Card>.from(deck.cardStack),
            currentPlayerIndex: currentPlayerIndex,
            scoreTracker: scoreTracker.copy(),
            reservedHands: {
              for (final e in reservedHands.entries)
                e.key: List<Card>.from(e.value),
            },
            phase: phase,
          )
          ..consecutivePasses = consecutivePasses
          ..lastPlayedBy = lastPlayedBy
          ..lastPlayedTurn = lastPlayedTurn
          ..lastDragonGiveBy = lastDragonGiveBy
          ..lastDragonGiveTo = lastDragonGiveTo
          ..pendingDragonGiveBy = pendingDragonGiveBy;
    c.pendingDragonGiveTargets.addAll(pendingDragonGiveTargets);
    c.pendingDragonTrickCards.addAll(pendingDragonTrickCards);
    c.currentTrickCards.addAll(currentTrickCards);
    c.finishedPlayers.addAll(finishedPlayers);
    c.playersWhoPlayedCardsThisRound.addAll(playersWhoPlayedCardsThisRound);
    c.roundLog.addAll(roundLog);
    c.bombDeclines.addAll(bombDeclines);
    c.grandTichuDecisions.addAll(grandTichuDecisions);
    c.schupfSelections.addAll(schupfSelections);
    c.completedSchupfSelections.addAll(completedSchupfSelections);
    for (final e in schupfReceipts.entries) {
      c.schupfReceipts[e.key] = List<SchupfReceipt>.from(e.value);
    }
    for (final e in schupfPendingAdditions.entries) {
      c.schupfPendingAdditions[e.key] = List<Card>.from(e.value);
    }
    return c;
  }
}
