import 'dart:math';

import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/find_turn.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/turn_handler.dart';
import 'package:tichu/game/turn/utils/engine/dealing.dart';
import 'package:tichu/game/turn/utils/engine/grand_tichu.dart';
import 'package:tichu/game/turn/utils/engine/schupf.dart' as schupf_utils;
import 'package:tichu/game/turn/utils/engine/snapshots.dart';
import 'package:tichu/game/turn/utils/engine/trick_resolution.dart';
import 'package:tichu/game/turn/utils/engine/turn_order.dart';

class GameEngineImpl implements GameEngine {
  final TurnHandler _turnHandler;
  final Random _random;

  GameEngineImpl({final TurnHandler? turnHandler, final Random? random})
    : _turnHandler = turnHandler ?? TurnHandler(),
      _random = random ?? Random();

  @override
  GameEngineState createGame({
    required final String gameId,
    required final List<GamePlayer> players,
    final int targetScore = 1000,
  }) {
    if (players.length != 4) {
      throw ArgumentError('Local mode currently supports exactly 4 players.');
    }

    final (hands, reserved) = dealInitialHands(players, _random);
    final state = GameEngineState(
      gameId: gameId,
      players: players,
      hands: hands,
      deck: DeckState(TichuTurn(TurnType.empty, const []), CardFace.none),
      currentPlayerIndex: 0,
      scoreTracker: LocalScoreTracker(targetScore: targetScore),
      reservedHands: reserved,
      phase: GamePhase.grandTichu,
    );

    state.scoreTracker.startNewRound(players);
    state.grandTichuDecisions.clear();
    state.schupfSelections.clear();
    state.completedSchupfSelections.clear();
    state.schupfReceipts.clear();
    state.schupfPendingAdditions.clear();
    state.playersWhoPlayedCardsThisRound.clear();
    state.roundLog.clear();
    return state;
  }

  @override
  void startNewRound(final GameEngineState state) {
    if (state.scoreTracker.state.gameComplete) {
      throw StateError('Game has ended. Start a new game to play again.');
    }

    final (hands, reserved) = dealInitialHands(state.players, _random);
    state.hands
      ..clear()
      ..addAll(hands);
    state.deck = DeckState(TichuTurn(TurnType.empty, const []), CardFace.none);
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
    state.roundLog.clear();
    state.grandTichuDecisions.clear();
    state.schupfSelections.clear();
    state.completedSchupfSelections.clear();
    state.schupfReceipts.clear();
    state.schupfPendingAdditions.clear();
    state.scoreTracker.startNewRound(state.players);
  }

  @override
  void startGame(final GameEngineState state) {
    state.grandTichuDecisions.clear();
    state.schupfSelections.clear();
    state.completedSchupfSelections.clear();
    state.schupfReceipts.clear();
    state.schupfPendingAdditions.clear();
    state.lastDragonGiveBy = null;
    state.lastDragonGiveTo = null;
    state.playersWhoPlayedCardsThisRound.clear();
    state.roundLog.clear();
  }

  @override
  void applyAction(final GameEngineState state, final GameAction action) {
    if (action is ConfirmOpponentTurnAction) {
      return;
    }

    if (action is AcknowledgeSchupfAction) {
      schupf_utils.applyAcknowledgeSchupf(state, action);
      return;
    }

    if (schupf_utils.hasPendingSchupfReceiptsForPlayer(
      state,
      action.playerId,
    )) {
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
      } else if (action is CallTichuAction) {
        if (!canPlayerCallTichu(state, action.playerId)) {
          throw StateError(
            'Tichu can only be called before playing your first card.',
          );
        }
        state.scoreTracker.recordTichuCall(action.playerId, isGrand: false);
        applyGrandTichuDecision(
          state,
          GrandTichuDecisionAction(playerId: action.playerId, call: false),
        );
      } else {
        throw StateError('Grand tichu decision required before play.');
      }
      return;
    }

    if (state.phase == GamePhase.schupf) {
      if (action is SchupfAction) {
        schupf_utils.applySchupfSelection(state, action);
        return;
      }
      if (action is CallTichuAction) {
        if (!canPlayerCallTichu(state, action.playerId)) {
          throw StateError(
            'Tichu can only be called before playing your first card.',
          );
        }
        state.scoreTracker.recordTichuCall(action.playerId, isGrand: false);
        return;
      }
      throw StateError('Schupfen required before play.');
    }

    // Tichu may be called at any time before the player's first card,
    // not only on their own turn.
    if (action is CallTichuAction) {
      if (!canPlayerCallTichu(state, action.playerId)) {
        throw StateError(
          'Tichu can only be called before playing your first card.',
        );
      }
      state.scoreTracker.recordTichuCall(action.playerId, isGrand: false);
      return;
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
          throw StateError("Not this player's turn.");
        }
      } else {
        throw StateError("Not this player's turn.");
      }
    }

    if (action is PlayTurnAction) {
      applyPlayAction(state, action, _turnHandler);
    } else if (action is PassAction) {
      applyPassAction(state, action);
    } else if (action is GiveDragonAction) {
      throw StateError('No dragon trick to give.');
    } else if (action is CallGrandTichuAction) {
      state.scoreTracker.recordTichuCall(action.playerId, isGrand: true);
    }
  }

  @override
  GameSnapshot buildSnapshot(
    final GameEngineState state, {
    final String? pendingOpponentPlayerId,
    final List<Card>? pendingOpponentCards,
    final bool pendingOpponentPass = false,
    final bool opponentAwaitingConfirmation = false,
  }) => buildGameSnapshot(
    state,
    pendingOpponentPlayerId: pendingOpponentPlayerId,
    pendingOpponentCards: pendingOpponentCards,
    pendingOpponentPass: pendingOpponentPass,
    opponentAwaitingConfirmation: opponentAwaitingConfirmation,
  );

  @override
  PlayerSnapshot buildPlayerSnapshot(
    final GameSnapshot snapshot,
    final String playerId,
  ) => buildPlayerView(snapshot, playerId);

  @override
  bool hasPendingHumanSchupfReceipts(final GameEngineState state) =>
      schupf_utils.hasPendingHumanSchupfReceipts(state);

  @override
  bool shouldPauseForAutomatedOpponent(
    final GameEngineState state,
    final String actorId,
  ) {
    final actor = state.players.firstWhere(
      (final player) => player.id == actorId,
    );
    if (actor.type != PlayerType.automated) return false;
    if (state.scoreTracker.state.roundComplete) return false;
    if (state.scoreTracker.state.gameComplete) return false;
    final anyHumanOut = state.players
        .where((final player) => player.type == PlayerType.human)
        .any((final player) => (state.hands[player.id] ?? const []).isEmpty);
    if (anyHumanOut) return false;
    final nextPlayer = state.players[state.currentPlayerIndex];
    return nextPlayer.type == PlayerType.automated;
  }

  @override
  List<String> opponentIds(
    final GameEngineState state,
    final String playerId,
  ) => opponentIdsForPlayer(state, playerId);
}
