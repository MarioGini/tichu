import 'dart:math';

import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/scoring/score_data.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/engine.dart';
import 'package:tichu/game/turn/utils/engine/dealing.dart';
import 'package:tichu/game/turn/utils/engine/grand_tichu.dart';
import 'package:tichu/game/turn/utils/engine/schupf.dart';
import 'package:tichu/game/turn/utils/engine/trick_resolution.dart';
import 'package:tichu/game/turn/utils/engine/turn_order.dart';
import 'package:tichu/game/turn/find_turn.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/turn_handler.dart';

class GameEngineImpl implements GameEngine {
  final TurnHandler _turnHandler;
  final Random _random;

  GameEngineImpl({TurnHandler? turnHandler, Random? random})
    : _turnHandler = turnHandler ?? TurnHandler(),
      _random = random ?? Random();

  @override
  GameEngineState createGame({
    required String gameId,
    required List<GamePlayer> players,
    int targetScore = 1000,
  }) {
    if (players.length != 4) {
      throw ArgumentError('Local mode currently supports exactly 4 players.');
    }

    final (hands, reserved) = dealInitialHands(players, _random);
    final state = GameEngineState(
      gameId: gameId,
      players: players,
      hands: hands,
      deck: DeckState(TichuTurn(TurnType.empty, []), CardFace.none),
      currentPlayerIndex: 0,
      scoreTracker: LocalScoreTracker(targetScore: targetScore),
      reservedHands: reserved,
      phase: GamePhase.grandTichu,
    );

    state.scoreTracker.startNewRound(players);
    state.grandTichuDecisions.clear();
    state.schupfSelections.clear();
    state.schupfReceipts.clear();
    state.playersWhoPlayedCardsThisRound.clear();
    return state;
  }

  @override
  void startNewRound(GameEngineState state) {
    if (state.scoreTracker.state.gameComplete) {
      throw StateError('Game has ended. Start a new game to play again.');
    }

    final (hands, reserved) = dealInitialHands(state.players, _random);
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
    state.currentTrickCards.clear();
    state.finishedPlayers.clear();
    state.playersWhoPlayedCardsThisRound.clear();
    state.grandTichuDecisions.clear();
    state.schupfSelections.clear();
    state.schupfReceipts.clear();
    state.scoreTracker.startNewRound(state.players);
  }

  @override
  void startGame(GameEngineState state) {
    state.grandTichuDecisions.clear();
    state.schupfSelections.clear();
    state.schupfReceipts.clear();
    state.lastDragonGiveBy = null;
    state.lastDragonGiveTo = null;
    state.playersWhoPlayedCardsThisRound.clear();
  }

  @override
  void applyAction(GameEngineState state, GameAction action) {
    if (action is ConfirmOpponentTurnAction) {
      return;
    }

    if (action is AcknowledgeSchupfAction) {
      applyAcknowledgeSchupf(state, action);
      return;
    }

    if (hasPendingSchupfReceiptsForPlayer(state, action.playerId)) {
      throw StateError('Accept schupf before continuing play.');
    }

    if (state.scoreTracker.state.roundComplete) {
      throw StateError('Round has ended. Start a new round to continue.');
    }

    if (state.phase == GamePhase.grandTichu) {
      final expectedPlayer = state.players[state.currentPlayerIndex].id;
      if (action.playerId != expectedPlayer) {
        throw StateError('Grand tichu decisions must be made in turn order.');
      }

      if (action is CallGrandTichuAction) {
        applyGrandTichuDecision(
          state,
          GrandTichuDecisionAction(playerId: action.playerId, call: true),
        );
      } else if (action is GrandTichuDecisionAction) {
        applyGrandTichuDecision(state, action);
      } else {
        throw StateError('Grand tichu decision required before play.');
      }
      return;
    }

    if (state.phase == GamePhase.schupf) {
      if (action is SchupfAction) {
        applySchupfSelection(state, action);
        return;
      }
      if (action is CallTichuAction) {
        if (!_canPlayerCallTichu(state, action.playerId)) {
          throw StateError(
            'Tichu can only be called before playing your first card.',
          );
        }
        state.scoreTracker.recordTichuCall(action.playerId, isGrand: false);
        return;
      }
      throw StateError('Schupfen required before play.');
    }

    if (state.pendingDragonGiveBy != null) {
      if (action is! GiveDragonAction ||
          action.playerId != state.pendingDragonGiveBy) {
        throw StateError('Dragon give required before continuing play.');
      }
      applyGiveDragonAction(state, action);
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
      applyPlayAction(state, action, _turnHandler);
    } else if (action is PassAction) {
      applyPassAction(state, action);
    } else if (action is GiveDragonAction) {
      throw StateError('No dragon trick to give.');
    } else if (action is CallTichuAction) {
      if (!_canPlayerCallTichu(state, action.playerId)) {
        throw StateError(
          'Tichu can only be called before playing your first card.',
        );
      }
      state.scoreTracker.recordTichuCall(action.playerId, isGrand: false);
    } else if (action is CallGrandTichuAction) {
      state.scoreTracker.recordTichuCall(action.playerId, isGrand: true);
    }
  }

  @override
  GameSnapshot buildSnapshot(
    GameEngineState state, {
    String? pendingOpponentPlayerId,
    List<Card>? pendingOpponentCards,
    bool pendingOpponentPass = false,
    bool opponentAwaitingConfirmation = false,
  }) {
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
          player.id: _canPlayerCallTichu(state, player.id),
      },
      grandTichuDecisions: Map<String, bool>.from(state.grandTichuDecisions),
      schupfCompletedPlayers: List<String>.from(state.schupfSelections.keys),
      schupfReceipts: Map<String, List<SchupfReceipt>>.from(
        state.schupfReceipts,
      ),
    );
  }

  @override
  PlayerSnapshot buildPlayerSnapshot(GameSnapshot snapshot, String playerId) {
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
      grandTichuDecisions: Map<String, bool>.from(snapshot.grandTichuDecisions),
      schupfCompletedPlayers: List<String>.from(
        snapshot.schupfCompletedPlayers,
      ),
      schupfReceipts: List<SchupfReceipt>.from(
        snapshot.schupfReceipts[playerId] ?? const <SchupfReceipt>[],
      ),
    );
  }

  bool _canPlayerCallTichu(GameEngineState state, String playerId) {
    if (state.phase != GamePhase.play && state.phase != GamePhase.schupf) {
      return false;
    }

    final playerCall = state.scoreTracker.state.tichuCalls[playerId];
    if (playerCall != null && playerCall != TichuCall.none) {
      return false;
    }

    return !state.playersWhoPlayedCardsThisRound.contains(playerId);
  }

  @override
  bool hasPendingHumanSchupfReceipts(GameEngineState state) {
    for (final player in state.players) {
      if (player.type != PlayerType.human) continue;
      final receipts = state.schupfReceipts[player.id];
      if (receipts != null && receipts.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  @override
  bool shouldPauseForAutomatedOpponent(GameEngineState state, String actorId) {
    final actor = state.players.firstWhere((player) => player.id == actorId);
    if (actor.type != PlayerType.automated) return false;
    if (state.scoreTracker.state.roundComplete) return false;
    if (state.scoreTracker.state.gameComplete) return false;
    final anyHumanOut = state.players
        .where((player) => player.type == PlayerType.human)
        .any((player) => (state.hands[player.id] ?? const []).isEmpty);
    if (anyHumanOut) return false;
    final nextPlayer = state.players[state.currentPlayerIndex];
    return nextPlayer.type == PlayerType.automated;
  }

  @override
  List<String> opponentIds(GameEngineState state, String playerId) {
    return opponentIdsForPlayer(state, playerId);
  }
}
