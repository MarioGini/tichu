import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

Card fxCard(CardFace face, CardColor color) => Card(face, color);

class FakePlayerAgent extends PlayerAgent {
  @override
  final String playerId;

  final GameAction action;
  final SchupfAction schupfAction;
  final int dragonSeat;

  FakePlayerAgent({
    required this.playerId,
    required this.action,
    required this.schupfAction,
    this.dragonSeat = 0,
  });

  @override
  Future<GameAction> selectAction(GameSnapshot snapshot) async => action;

  @override
  int selectDragonGive(GameSnapshot snapshot) => dragonSeat;

  @override
  Future<SchupfAction> selectSchupfCards(GameSnapshot snapshot) async =>
      schupfAction;

  @override
  Future<GameAction> selectTurn(GameSnapshot snapshot) async => action;

  @override
  Future<bool> shouldCallGrandTichu(GameSnapshot snapshot) async => false;

  @override
  Future<bool> shouldCallTichu(GameSnapshot snapshot) async => false;
}

class FakeEngine implements GameEngine {
  final List<GameAction> appliedActions = [];
  bool hasPendingHumanReceipts = false;
  bool shouldPause = false;
  List<String> opponentIdsResult = const <String>[];
  String? initialPendingDragonBy;

  GameEngineState buildState(String gameId, List<GamePlayer> players) {
    final score = LocalScoreTracker();
    score.startNewRound(players);
    final state = GameEngineState(
      gameId: gameId,
      players: players,
      hands: {
        for (final player in players)
          player.id: [fxCard(CardFace.two, CardColor.red)],
      },
      reservedHands: {for (final player in players) player.id: <Card>[]},
      deck: DeckState(TichuTurn(TurnType.empty, const []), CardFace.none),
      currentPlayerIndex: 0,
      scoreTracker: score,
      phase: GamePhase.play,
    );
    state.pendingDragonGiveBy = initialPendingDragonBy;
    if (initialPendingDragonBy != null && opponentIdsResult.isNotEmpty) {
      state.pendingDragonGiveTargets.addAll(opponentIdsResult);
      state.pendingDragonTrickCards.add(
        Card(CardFace.dragon, CardColor.special),
      );
    }
    return state;
  }

  @override
  GameEngineState createGame({
    required String gameId,
    required List<GamePlayer> players,
    int targetScore = 1000,
  }) => buildState(gameId, players);

  @override
  void applyAction(GameEngineState state, GameAction action) {
    appliedActions.add(action);
    if (action is PassAction || action is PlayTurnAction) {
      state.currentPlayerIndex =
          (state.currentPlayerIndex + 1) % state.players.length;
    }
    if (action is GiveDragonAction) {
      state.pendingDragonGiveBy = null;
      state.pendingDragonGiveTargets.clear();
      state.pendingDragonTrickCards.clear();
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
    schupfCompletedPlayers: const [],
    schupfReceipts: const {},
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
        schupfCompletedPlayers: const [],
        schupfReceipts: const [],
      );

  @override
  bool hasPendingHumanSchupfReceipts(GameEngineState state) =>
      hasPendingHumanReceipts;

  @override
  List<String> opponentIds(GameEngineState state, String playerId) =>
      opponentIdsResult;

  @override
  bool shouldPauseForAutomatedOpponent(GameEngineState state, String actorId) =>
      shouldPause;

  @override
  void startGame(GameEngineState state) {}

  @override
  void startNewRound(GameEngineState state) {}
}

final fxPlayers = <GamePlayer>[
  const GamePlayer(id: 'p0', name: 'P0', seat: 0, type: PlayerType.human),
  const GamePlayer(id: 'p1', name: 'P1', seat: 1, type: PlayerType.automated),
  const GamePlayer(id: 'p2', name: 'P2', seat: 2, type: PlayerType.human),
  const GamePlayer(id: 'p3', name: 'P3', seat: 3, type: PlayerType.human),
];

final automatedLeadPlayers = <GamePlayer>[
  const GamePlayer(id: 'p0', name: 'P0', seat: 0, type: PlayerType.automated),
  const GamePlayer(id: 'p1', name: 'P1', seat: 1, type: PlayerType.human),
  const GamePlayer(id: 'p2', name: 'P2', seat: 2, type: PlayerType.human),
  const GamePlayer(id: 'p3', name: 'P3', seat: 3, type: PlayerType.human),
];
