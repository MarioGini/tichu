import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'local_match_runtime_fakes.dart';

class SchupfFlowEngine implements GameEngine {
  final List<GameAction> appliedActions = [];

  @override
  GameEngineState createGame({
    required String gameId,
    required List<GamePlayer> players,
    int targetScore = 1000,
  }) {
    final score = LocalScoreTracker();
    score.startNewRound(players);
    return GameEngineState(
      gameId: gameId,
      players: players,
      hands: {
        for (final player in players)
          player.id: [
            fxCard(CardFace.two, CardColor.red),
            fxCard(CardFace.three, CardColor.red),
            fxCard(CardFace.four, CardColor.red),
          ],
      },
      reservedHands: {for (final player in players) player.id: <Card>[]},
      deck: DeckState(TichuTurn(TurnType.empty, const []), CardFace.none),
      currentPlayerIndex: 0,
      scoreTracker: score,
      phase: GamePhase.schupf,
    );
  }

  @override
  void applyAction(GameEngineState state, GameAction action) {
    appliedActions.add(action);
    if (action is SchupfAction) {
      state.schupfSelections[action.playerId] = action;
      state.phase = GamePhase.play;
      state.schupfReceipts['p0'] = [
        SchupfReceipt(
          card: fxCard(CardFace.five, CardColor.red),
          fromPlayerId: 'p1',
          direction: SchupfDirection.left,
        ),
      ];
      return;
    }
    if (action is AcknowledgeSchupfAction) {
      state.schupfReceipts.remove(action.playerId);
    }
  }

  @override
  GameSnapshot buildSnapshot(
    GameEngineState state, {
    String? pendingOpponentPlayerId,
    List<Card>? pendingOpponentCards,
    bool pendingOpponentPass = false,
    bool opponentAwaitingConfirmation = false,
  }) => GameSnapshot(
    gameId: state.gameId,
    players: state.players,
    hands: state.hands,
    deck: state.deck,
    trickPoints: 0,
    activeWish: state.deck.wish,
    currentPlayerId: state.players[state.currentPlayerIndex].id,
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
    grandTichuDecisions: const {},
    schupfCompletedPlayers: List<String>.from(state.schupfSelections.keys),
    schupfReceipts: Map<String, List<SchupfReceipt>>.from(state.schupfReceipts),
  );

  @override
  PlayerSnapshot buildPlayerSnapshot(GameSnapshot snapshot, String playerId) =>
      PlayerSnapshot(
        gameId: snapshot.gameId,
        players: snapshot.players,
        hand: List<Card>.from(snapshot.hands[playerId] ?? const <Card>[]),
        opponentCardCounts: {
          for (final p in snapshot.players)
            if (p.id != playerId)
              p.id: (snapshot.hands[p.id] ?? const <Card>[]).length,
        },
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
        grandTichuDecisions: const {},
        schupfCompletedPlayers: snapshot.schupfCompletedPlayers,
        schupfReceipts: List<SchupfReceipt>.from(
          snapshot.schupfReceipts[playerId] ?? const <SchupfReceipt>[],
        ),
      );

  @override
  bool hasPendingHumanSchupfReceipts(GameEngineState state) => false;

  @override
  List<String> opponentIds(GameEngineState state, String playerId) =>
      const <String>[];

  @override
  bool shouldPauseForAutomatedOpponent(GameEngineState state, String actorId) =>
      false;

  @override
  void startGame(GameEngineState state) {}

  @override
  void startNewRound(GameEngineState state) {}
}
