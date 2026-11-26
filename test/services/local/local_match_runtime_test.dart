import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_exceptions.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/services/local/local_match_runtime.dart';
import 'package:tichu/services/request_rejected_exception.dart';

import 'local_match_runtime_fakes.dart';
import 'schupf_flow_engine_fake.dart';

void main() {
  group('LocalMatchRuntime', () {
    test('throws for unknown game id operations', () async {
      final backend = LocalMatchRuntime(engine: FakeEngine());

      expect(
        () => backend.watchGameState('missing'),
        throwsA(isA<RequestRejectedException>()),
      );
      expect(
        () => backend.startGame('missing'),
        throwsA(isA<RequestRejectedException>()),
      );
      expect(
        () => backend.startNewRound('missing'),
        throwsA(isA<RequestRejectedException>()),
      );
      expect(
        () => backend.submitAction('missing', const PassAction(playerId: 'p0')),
        throwsA(isA<RequestRejectedException>()),
      );
    });

    test('createGame emits snapshots on start and new round', () async {
      final backend = LocalMatchRuntime(engine: FakeEngine());
      final gameId = await backend.createGame(fxPlayers);

      final gameStream = backend.watchGameState(gameId);
      final snapshotFuture = gameStream.first;
      await backend.startGame(gameId);
      final snapshot = await snapshotFuture;
      expect(snapshot.gameId, gameId);

      final roundSnapshotFuture = backend.watchGameState(gameId).first;
      await backend.startNewRound(gameId);
      final roundSnapshot = await roundSnapshotFuture;
      expect(roundSnapshot.gameId, gameId);
      await backend.disposeGame(gameId);
    });

    test('blocks new action while awaiting opponent confirmation', () async {
      final engine = FakeEngine()..shouldPause = true;
      final backend = LocalMatchRuntime(engine: engine);
      final gameId = await backend.createGame(fxPlayers);

      await backend.submitAction(
        gameId,
        PlayTurnAction(
          playerId: 'p0',
          cards: [Card(CardFace.two, CardColor.red)],
        ),
      );

      expect(
        () => backend.submitAction(gameId, const PassAction(playerId: 'p0')),
        throwsA(isA<IllegalActionException>()),
      );

      await backend.disposeGame(gameId);
    });

    test('confirm applies pending automated opponent action', () async {
      final engine = FakeEngine();
      final automatedAgent = FakePlayerAgent(
        playerId: 'p0',
        action: const PassAction(playerId: 'p0'),
        schupfAction: SchupfAction(
          playerId: 'p0',
          toLeft: Card(CardFace.two, CardColor.red),
          toPartner: Card(CardFace.three, CardColor.red),
          toRight: Card(CardFace.four, CardColor.red),
        ),
      );
      final backend = LocalMatchRuntime(
        engine: engine,
        automatedAgents: {'p0': automatedAgent},
      );

      final gameId = await backend.createGame(automatedLeadPlayers);
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
      final engine = FakeEngine()
        ..initialPendingDragonBy = 'p0'
        ..opponentIdsResult = ['p1', 'p3'];
      final automatedAgent = FakePlayerAgent(
        playerId: 'p0',
        action: const PassAction(playerId: 'p0'),
        schupfAction: SchupfAction(
          playerId: 'p0',
          toLeft: Card(CardFace.two, CardColor.red),
          toPartner: Card(CardFace.three, CardColor.red),
          toRight: Card(CardFace.four, CardColor.red),
        ),
      );
      final backend = LocalMatchRuntime(
        engine: engine,
        automatedAgents: {'p0': automatedAgent},
      );

      final gameId = await backend.createGame(automatedLeadPlayers);
      await backend.startGame(gameId);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(engine.appliedActions.whereType<GiveDragonAction>(), hasLength(1));
      await backend.disposeGame(gameId);
    });

    test('auto acknowledges schupf receipts for automated players', () async {
      final engine = SchupfFlowEngine();
      final automatedAgent = FakePlayerAgent(
        playerId: 'p0',
        action: const PassAction(playerId: 'p0'),
        schupfAction: SchupfAction(
          playerId: 'p0',
          toLeft: Card(CardFace.two, CardColor.red),
          toPartner: Card(CardFace.three, CardColor.red),
          toRight: Card(CardFace.four, CardColor.red),
        ),
      );
      final backend = LocalMatchRuntime(
        engine: engine,
        automatedAgents: {'p0': automatedAgent},
      );

      await backend.setAutomatedActionDelay(Duration.zero);
      final gameId = await backend.createGame(automatedLeadPlayers);
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
