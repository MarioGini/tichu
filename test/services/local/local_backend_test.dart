import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/services/local/local_backend.dart';

Card _card(final CardFace face, final CardColor color) => Card(face, color);

class _FakePlayerAgent extends PlayerAgent {
  @override
  final String playerId;

  final GameAction action;
  final SchupfAction schupfAction;
  final int dragonSeat;

  _FakePlayerAgent({
    required this.playerId,
    required this.action,
    required this.schupfAction,
    // ignore: unused_element_parameter, required by PlayerAgent interface
    this.dragonSeat = 0,
  });

  @override
  Future<GameAction> selectAction(final GameSnapshot snapshot) async => action;

  @override
  int selectDragonGive(final GameSnapshot snapshot) => dragonSeat;

  @override
  Future<SchupfAction> selectSchupfCards(final GameSnapshot snapshot) async =>
      schupfAction;

  @override
  Future<GameAction> selectTurn(final GameSnapshot snapshot) async => action;

  @override
  Future<bool> shouldCallGrandTichu(final GameSnapshot snapshot) async => false;

  @override
  Future<bool> shouldCallTichu(final GameSnapshot snapshot) async => false;
}

class _FakeEngine implements GameEngine {
  final List<GameAction> appliedActions = [];
  bool hasPendingHumanReceipts = false;
  bool shouldPause = false;
  List<String> opponentIdsResult = const <String>[];
  String? initialPendingDragonBy;

  GameEngineState _buildState(final String gameId, final List<GamePlayer> players) {
    final score = LocalScoreTracker();
    score.startNewRound(players);
    final state = GameEngineState(
      gameId: gameId,
      players: players,
      hands: {
        for (final player in players)
          player.id: [_card(CardFace.two, CardColor.red)],
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
    required final String gameId,
    required final List<GamePlayer> players,
    final int targetScore = 1000,
  }) => _buildState(gameId, players);

  @override
  void applyAction(final GameEngineState state, final GameAction action) {
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
    final GameEngineState state, {
    final String? pendingOpponentPlayerId,
    final List<Card>? pendingOpponentCards,
    final bool pendingOpponentPass = false,
    final bool opponentAwaitingConfirmation = false,
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
      grandTichuDecisions: const {},
      schupfCompletedPlayers: const [],
      schupfReceipts: const {},
    );

  @override
  PlayerSnapshot buildPlayerSnapshot(final GameSnapshot snapshot, final String playerId) => PlayerSnapshot(
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
  bool hasPendingHumanSchupfReceipts(final GameEngineState state) =>
      hasPendingHumanReceipts;

  @override
  List<String> opponentIds(final GameEngineState state, final String playerId) =>
      opponentIdsResult;

  @override
  bool shouldPauseForAutomatedOpponent(final GameEngineState state, final String actorId) =>
      shouldPause;

  @override
  void startGame(final GameEngineState state) {}

  @override
  void startNewRound(final GameEngineState state) {}
}

class _SchupfFlowEngine implements GameEngine {
  final List<GameAction> appliedActions = [];

  @override
  GameEngineState createGame({
    required final String gameId,
    required final List<GamePlayer> players,
    final int targetScore = 1000,
  }) {
    final score = LocalScoreTracker();
    score.startNewRound(players);
    return GameEngineState(
      gameId: gameId,
      players: players,
      hands: {
        for (final player in players)
          player.id: [
            _card(CardFace.two, CardColor.red),
            _card(CardFace.three, CardColor.red),
            _card(CardFace.four, CardColor.red),
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
  void applyAction(final GameEngineState state, final GameAction action) {
    appliedActions.add(action);
    if (action is SchupfAction) {
      state.schupfSelections[action.playerId] = action;
      state.phase = GamePhase.play;
      state.schupfReceipts['p0'] = [
        SchupfReceipt(
          card: _card(CardFace.five, CardColor.red),
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
    final GameEngineState state, {
    final String? pendingOpponentPlayerId,
    final List<Card>? pendingOpponentCards,
    final bool pendingOpponentPass = false,
    final bool opponentAwaitingConfirmation = false,
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
      grandTichuDecisions: const {},
      schupfCompletedPlayers: List<String>.from(state.schupfSelections.keys),
      schupfReceipts: Map<String, List<SchupfReceipt>>.from(
        state.schupfReceipts,
      ),
    );

  @override
  PlayerSnapshot buildPlayerSnapshot(final GameSnapshot snapshot, final String playerId) => PlayerSnapshot(
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
  bool hasPendingHumanSchupfReceipts(final GameEngineState state) => false;

  @override
  List<String> opponentIds(final GameEngineState state, final String playerId) =>
      const <String>[];

  @override
  bool shouldPauseForAutomatedOpponent(final GameEngineState state, final String actorId) =>
      false;

  @override
  void startGame(final GameEngineState state) {}

  @override
  void startNewRound(final GameEngineState state) {}
}

final _players = <GamePlayer>[
  const GamePlayer(id: 'p0', name: 'P0', seat: 0, type: PlayerType.human),
  const GamePlayer(id: 'p1', name: 'P1', seat: 1, type: PlayerType.automated),
  const GamePlayer(id: 'p2', name: 'P2', seat: 2, type: PlayerType.human),
  const GamePlayer(id: 'p3', name: 'P3', seat: 3, type: PlayerType.human),
];

final _automatedLeadPlayers = <GamePlayer>[
  const GamePlayer(id: 'p0', name: 'P0', seat: 0, type: PlayerType.automated),
  const GamePlayer(id: 'p1', name: 'P1', seat: 1, type: PlayerType.human),
  const GamePlayer(id: 'p2', name: 'P2', seat: 2, type: PlayerType.human),
  const GamePlayer(id: 'p3', name: 'P3', seat: 3, type: PlayerType.human),
];

void main() {
  group('LocalGameBackend', () {
    test('throws for unknown game id operations', () async {
      final backend = LocalGameBackend(engine: _FakeEngine());

      expect(() => backend.watchGame('missing', 'p0'), throwsStateError);
      expect(() => backend.watchGameState('missing'), throwsStateError);
      expect(() => backend.startGame('missing'), throwsStateError);
      expect(() => backend.startNewRound('missing'), throwsStateError);
      expect(
        () => backend.submitAction('missing', const PassAction(playerId: 'p0')),
        throwsStateError,
      );
    });

    test('createGame emits snapshots and watchGame maps player view', () async {
      final backend = LocalGameBackend(engine: _FakeEngine());
      final gameId = await backend.createGame(_players);

      final gameStream = backend.watchGameState(gameId);
      final snapshotFuture = gameStream.first;
      await backend.startGame(gameId);
      final snapshot = await snapshotFuture;
      expect(snapshot.gameId, gameId);

      final playerStream = backend.watchGame(gameId, 'p0');
      final playerSnapshotFuture = playerStream.first;
      await backend.startNewRound(gameId);
      final playerSnapshot = await playerSnapshotFuture;
      expect(playerSnapshot.hand, hasLength(1));
      await backend.disposeGame(gameId);
    });

    test('blocks new action while awaiting opponent confirmation', () async {
      final engine = _FakeEngine()..shouldPause = true;
      final backend = LocalGameBackend(engine: engine);
      final gameId = await backend.createGame(_players);

      await backend.submitAction(
        gameId,
        PlayTurnAction(
          playerId: 'p0',
          cards: [Card(CardFace.two, CardColor.red)],
        ),
      );

      expect(
        () => backend.submitAction(gameId, const PassAction(playerId: 'p0')),
        throwsStateError,
      );

      await backend.disposeGame(gameId);
    });

    test('confirm applies pending automated opponent action', () async {
      final engine = _FakeEngine();
      final automatedAgent = _FakePlayerAgent(
        playerId: 'p0',
        action: const PassAction(playerId: 'p0'),
        schupfAction: SchupfAction(
          playerId: 'p0',
          toLeft: Card(CardFace.two, CardColor.red),
          toPartner: Card(CardFace.three, CardColor.red),
          toRight: Card(CardFace.four, CardColor.red),
        ),
      );
      final backend = LocalGameBackend(
        engine: engine,
        automatedAgents: {'p0': automatedAgent},
      );

      final gameId = await backend.createGame(_automatedLeadPlayers);
      await backend.startGame(gameId);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await backend.submitAction(
        gameId,
        const ConfirmOpponentTurnAction(playerId: 'p1'),
      );

      expect(
        engine.appliedActions.whereType<PassAction>().length,
        greaterThanOrEqualTo(1),
      );
      await backend.disposeGame(gameId);
    });

    test('auto resolves dragon give for automated winner', () async {
      final engine = _FakeEngine()
        ..initialPendingDragonBy = 'p0'
        ..opponentIdsResult = ['p1', 'p3'];
      final automatedAgent = _FakePlayerAgent(
        playerId: 'p0',
        action: const PassAction(playerId: 'p0'),
        schupfAction: SchupfAction(
          playerId: 'p0',
          toLeft: Card(CardFace.two, CardColor.red),
          toPartner: Card(CardFace.three, CardColor.red),
          toRight: Card(CardFace.four, CardColor.red),
        ),
      );
      final backend = LocalGameBackend(
        engine: engine,
        automatedAgents: {'p0': automatedAgent},
      );

      final gameId = await backend.createGame(_automatedLeadPlayers);
      await backend.startGame(gameId);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(engine.appliedActions.whereType<GiveDragonAction>(), hasLength(1));
      await backend.disposeGame(gameId);
    });

    test('auto acknowledges schupf receipts for automated players', () async {
      final engine = _SchupfFlowEngine();
      final automatedAgent = _FakePlayerAgent(
        playerId: 'p0',
        action: const PassAction(playerId: 'p0'),
        schupfAction: SchupfAction(
          playerId: 'p0',
          toLeft: Card(CardFace.two, CardColor.red),
          toPartner: Card(CardFace.three, CardColor.red),
          toRight: Card(CardFace.four, CardColor.red),
        ),
      );
      final backend = LocalGameBackend(
        engine: engine,
        automatedAgents: {'p0': automatedAgent},
      );

      await backend.setAutomatedActionDelay(Duration.zero);
      final gameId = await backend.createGame(_automatedLeadPlayers);
      await backend.startGame(gameId);

      expect(engine.appliedActions.whereType<SchupfAction>(), hasLength(1));
      expect(
        engine.appliedActions.whereType<AcknowledgeSchupfAction>(),
        hasLength(1),
      );
      await backend.disposeGame(gameId);
    });
  });
}
