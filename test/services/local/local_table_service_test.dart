import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_match.dart';
import 'package:tichu/game/game_session.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/services/local/local_match_runtime.dart';
import 'package:tichu/services/local/local_table_service.dart';

Card _card(final CardFace face, final CardColor color) => Card(face, color);

final List<_PlayerSeed> _playerSeeds = <_PlayerSeed>[
  const _PlayerSeed('Host', 0),
  const _PlayerSeed('North', 1),
  const _PlayerSeed('Partner', 2),
  const _PlayerSeed('South', 3),
];

class _PlayerSeed {
  final String displayName;
  final int seat;

  const _PlayerSeed(this.displayName, this.seat);
}

class _StaticMultiplayerEngine implements GameEngine {
  GameEngineState _buildState(
    final String gameId,
    final List<GamePlayer> players,
    final int targetScore,
  ) {
    final score = LocalScoreTracker(targetScore: targetScore)
      ..startNewRound(players);
    final hands = <String, List<Card>>{};
    for (final player in players) {
      hands[player.id] = <Card>[
        _card(CardFace.values[CardFace.two.index + player.seat], CardColor.red),
      ];
    }
    return GameEngineState(
      gameId: gameId,
      players: players,
      hands: hands,
      reservedHands: {for (final player in players) player.id: <Card>[]},
      deck: DeckState(TichuTurn(TurnType.empty, const <Card>[]), CardFace.none),
      currentPlayerIndex: 0,
      scoreTracker: score,
      phase: GamePhase.play,
    );
  }

  @override
  GameEngineState createGame({
    required final String gameId,
    required final List<GamePlayer> players,
    final int targetScore = 1000,
  }) => _buildState(gameId, players, targetScore);

  @override
  void startNewRound(final GameEngineState state) {
    state.scoreTracker.startNewRound(state.players);
    state.currentPlayerIndex = 0;
    state.consecutivePasses = 0;
    state.lastPlayedBy = null;
    state.lastPlayedTurn = null;
    state.deck = DeckState(
      TichuTurn(TurnType.empty, const <Card>[]),
      CardFace.none,
    );
  }

  @override
  void startGame(final GameEngineState state) {}

  @override
  void applyAction(final GameEngineState state, final GameAction action) {
    switch (action) {
      case PlayTurnAction():
        final hand = state.hands[action.playerId] ?? <Card>[];
        action.cards.forEach(hand.remove);
        state.lastPlayedBy = action.playerId;
        state.lastPlayedTurn = TichuTurn(TurnType.single, action.cards);
        state.deck = DeckState(state.lastPlayedTurn!, CardFace.none)
          ..currentWinner = action.playerId;
        state.currentPlayerIndex =
            (state.currentPlayerIndex + 1) % state.players.length;
      case PassAction():
        state.lastPlayedBy = action.playerId;
        state.lastPlayedTurn = TichuTurn(TurnType.none, const <Card>[]);
        state.currentPlayerIndex =
            (state.currentPlayerIndex + 1) % state.players.length;
      default:
        break;
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
    hands: {
      for (final entry in state.hands.entries)
        entry.key: List<Card>.from(entry.value),
    },
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
    grandTichuDecisions: const <String, bool>{},
    schupfCompletedPlayers: const <String>[],
    schupfReceipts: const <String, List<SchupfReceipt>>{},
  );

  @override
  PlayerSnapshot buildPlayerSnapshot(
    final GameSnapshot snapshot,
    final String playerId,
  ) => PlayerSnapshot(
    gameId: snapshot.gameId,
    players: snapshot.players,
    hand: List<Card>.from(snapshot.hands[playerId] ?? const <Card>[]),
    opponentCardCounts: {
      for (final player in snapshot.players)
        if (player.id != playerId)
          player.id: (snapshot.hands[player.id] ?? const <Card>[]).length,
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
    pendingDragonGiveTargets: List<String>.from(
      snapshot.pendingDragonGiveTargets,
    ),
    pendingOpponentPlayerId: snapshot.pendingOpponentPlayerId,
    pendingOpponentCards: List<Card>.from(snapshot.pendingOpponentCards),
    pendingOpponentPass: snapshot.pendingOpponentPass,
    scoreState: snapshot.scoreState,
    opponentAwaitingConfirmation: snapshot.opponentAwaitingConfirmation,
    phase: snapshot.phase,
    grandTichuDecisions: const <String, bool>{},
    schupfCompletedPlayers: const <String>[],
    schupfReceipts: const <SchupfReceipt>[],
  );

  @override
  bool hasPendingHumanSchupfReceipts(final GameEngineState state) => false;

  @override
  bool shouldPauseForAutomatedOpponent(
    final GameEngineState state,
    final String actorId,
  ) => false;

  @override
  List<String> opponentIds(
    final GameEngineState state,
    final String playerId,
  ) => <String>[
    for (final player in state.players)
      if (player.id != playerId) player.id,
  ];
}

Future<List<GameSessionHandle>> _createHumanTable(
  final LocalGameTableService service,
) async {
  final host = await service.createLobby(
    CreateGameLobbyRequest(displayName: _playerSeeds.first.displayName),
  );
  await service.claimSeat(
    host.lobbyId,
    accessToken: host.accessToken,
    seat: _playerSeeds.first.seat,
  );
  await service.setReadyState(
    host.lobbyId,
    accessToken: host.accessToken,
    isReady: true,
  );

  final lobby = await service
      .watchLobby(host.lobbyId, accessToken: host.accessToken)
      .first;

  final handles = <GameSessionHandle>[host];
  for (final seed in _playerSeeds.skip(1)) {
    final handle = await service.joinLobby(
      JoinGameLobbyRequest(
        joinCode: lobby.joinCode!,
        displayName: seed.displayName,
      ),
    );
    await service.claimSeat(
      handle.lobbyId,
      accessToken: handle.accessToken,
      seat: seed.seat,
    );
    await service.setReadyState(
      handle.lobbyId,
      accessToken: handle.accessToken,
      isReady: true,
    );
    handles.add(handle);
  }

  await service.startMatch(host.lobbyId, accessToken: host.accessToken);
  final activeLobby = await service
      .watchLobby(host.lobbyId, accessToken: host.accessToken)
      .firstWhere((final snapshot) => snapshot.matchId != null);

  return [
    for (final handle in handles) handle.copyWith(matchId: activeLobby.matchId),
  ];
}

void main() {
  group('LocalGameTableService multiplayer contract', () {
    late _StaticMultiplayerEngine engine;
    late LocalGameTableService service;

    setUp(() {
      engine = _StaticMultiplayerEngine();
      service = LocalGameTableService(
        runtimeFactory: () => LocalMatchRuntime(engine: engine),
        projectionEngine: engine,
      );
    });

    test('streams player-specific match views for multiple humans', () async {
      final handles = await _createHumanTable(service);
      final host = handles[0];
      final partner = handles[2];
      final matchId = host.matchId!;

      final hostView = await service
          .watchMatch(matchId, accessToken: host.accessToken)
          .first;
      final partnerView = await service
          .watchMatch(matchId, accessToken: partner.accessToken)
          .first;

      expect(hostView.selfPlayerId, host.playerId);
      expect(partnerView.selfPlayerId, partner.playerId);
      expect(hostView.snapshot.hand, isNotEmpty);
      expect(partnerView.snapshot.hand, isNotEmpty);
      expect(hostView.snapshot.hand, isNot(partnerView.snapshot.hand));
      expect(hostView.snapshot.players, hasLength(4));
      expect(partnerView.snapshot.opponentCardCounts[host.playerId], 1);
    });

    test(
      'rejects stale expected revisions after another player moves',
      () async {
        final handles = await _createHumanTable(service);
        final host = handles[0];
        final nextPlayer = handles[1];
        final matchId = host.matchId!;

        final initialView = await service
            .watchMatch(matchId, accessToken: host.accessToken)
            .first;
        final staleRevision = initialView.revision;

        await service.submitAction(
          matchId,
          GameActionSubmission(
            clientActionId: 'host-pass-1',
            action: PassAction(playerId: host.playerId),
            expectedRevision: staleRevision,
          ),
          accessToken: host.accessToken,
        );

        final updatedView = await service
            .watchMatch(matchId, accessToken: nextPlayer.accessToken)
            .first;
        expect(updatedView.revision, greaterThan(staleRevision));

        await expectLater(
          () => service.submitAction(
            matchId,
            GameActionSubmission(
              clientActionId: 'next-pass-stale',
              action: PassAction(playerId: nextPlayer.playerId),
              expectedRevision: staleRevision,
            ),
            accessToken: nextPlayer.accessToken,
          ),
          throwsStateError,
        );
      },
    );

    test('deduplicates repeated client action ids', () async {
      final handles = await _createHumanTable(service);
      final host = handles[0];
      final matchId = host.matchId!;

      final initialView = await service
          .watchMatch(matchId, accessToken: host.accessToken)
          .first;

      await service.submitAction(
        matchId,
        GameActionSubmission(
          clientActionId: 'retryable-pass',
          action: PassAction(playerId: host.playerId),
          expectedRevision: initialView.revision,
        ),
        accessToken: host.accessToken,
      );

      final afterFirstSubmit = await service
          .watchMatch(matchId, accessToken: host.accessToken)
          .first;

      await service.submitAction(
        matchId,
        GameActionSubmission(
          clientActionId: 'retryable-pass',
          action: PassAction(playerId: host.playerId),
          expectedRevision: initialView.revision,
        ),
        accessToken: host.accessToken,
      );

      final afterDuplicateSubmit = await service
          .watchMatch(matchId, accessToken: host.accessToken)
          .first;

      expect(afterFirstSubmit.revision, greaterThan(initialView.revision));
      expect(afterDuplicateSubmit.revision, afterFirstSubmit.revision);
    });
  });
}
