import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_exceptions.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import '../../../utils/test_game_fixtures.dart';
import 'engine_test_fixtures.dart';

void main() {
  group('GameEngineImpl.createGame', () {
    test('throws when player count is not four', () {
      final engine = GameEngineImpl();

      expect(
        () => engine.createGame(
          gameId: 'g1',
          players: testPlayers.take(3).toList(),
        ),
        throwsArgumentError,
      );
    });
  });

  group('GameEngineImpl.applyAction guards', () {
    test('requires grand tichu decision during grand tichu phase', () {
      final engine = GameEngineImpl();
      final state = fxState(phase: GamePhase.grandTichu);

      expect(
        () =>
            engine.applyAction(state, const PassAction(playerId: testHumanId)),
        throwsA(isA<IllegalActionException>()),
      );
    });

    test('rejects out-of-turn grand tichu decision', () {
      final engine = GameEngineImpl();
      final state = fxState(phase: GamePhase.grandTichu);

      expect(
        () => engine.applyAction(
          state,
          const GrandTichuDecisionAction(
            playerId: testOpponentLeftId,
            call: false,
          ),
        ),
        throwsA(isA<IllegalActionException>()),
      );
    });

    test('allows calling tichu during grand tichu phase', () {
      final engine = GameEngineImpl();
      final state = fxState(phase: GamePhase.grandTichu);

      engine.applyAction(state, const CallTichuAction(playerId: testHumanId));

      expect(state.scoreTracker.state.tichuCalls[testHumanId], TichuCall.tichu);
      expect(state.grandTichuDecisions[testHumanId], isFalse);
      expect(state.currentPlayerIndex, 1);
    });

    test('disallows grand tichu if player already called tichu', () {
      final engine = GameEngineImpl();
      final state = fxState(phase: GamePhase.grandTichu);

      engine.applyAction(state, const CallTichuAction(playerId: testHumanId));

      engine.applyAction(
        state,
        const GrandTichuDecisionAction(
          playerId: testOpponentLeftId,
          call: false,
        ),
      );
      engine.applyAction(
        state,
        const GrandTichuDecisionAction(
          playerId: testOpponentPartnerId,
          call: false,
        ),
      );
      engine.applyAction(
        state,
        const GrandTichuDecisionAction(
          playerId: testOpponentRightId,
          call: false,
        ),
      );

      expect(state.scoreTracker.state.tichuCalls[testHumanId], TichuCall.tichu);
      expect(
        state.scoreTracker.state.tichuCalls[testHumanId],
        isNot(TichuCall.grandTichu),
      );
    });

    test('requires schupf action during schupf phase', () {
      final engine = GameEngineImpl();
      final state = fxState(phase: GamePhase.schupf);

      expect(
        () =>
            engine.applyAction(state, const PassAction(playerId: testHumanId)),
        throwsA(isA<IllegalActionException>()),
      );
    });

    test('allows tichu call during schupf phase', () {
      final engine = GameEngineImpl();
      final state = fxState(phase: GamePhase.schupf);

      engine.applyAction(state, const CallTichuAction(playerId: testHumanId));

      final tichuCall = state.scoreTracker.state.tichuCalls[testHumanId];
      expect(tichuCall, TichuCall.tichu);
    });

    test('allows calling tichu off-turn during play', () {
      final engine = GameEngineImpl();
      final state = fxState(phase: GamePhase.play);
      final notCurrent = state.players
          .firstWhere(
            (final p) => p.id != state.players[state.currentPlayerIndex].id,
          )
          .id;

      engine.applyAction(state, CallTichuAction(playerId: notCurrent));

      expect(state.scoreTracker.state.tichuCalls[notCurrent], TichuCall.tichu);
    });

    test('blocks non dragon action while dragon give is pending', () {
      final engine = GameEngineImpl();
      final state = fxState(phase: GamePhase.play);
      state.pendingDragonGiveBy = testOpponentLeftId;
      state.pendingDragonGiveTargets.addAll([
        testHumanId,
        testOpponentPartnerId,
      ]);

      expect(
        () =>
            engine.applyAction(state, const PassAction(playerId: testHumanId)),
        throwsA(isA<IllegalActionException>()),
      );
    });

    test('rejects out-of-turn non-bomb play', () {
      final engine = GameEngineImpl();
      final state = fxState(
        phase: GamePhase.play,
        deck: DeckState(
          TichuTurn(TurnType.single, [fxCard(CardFace.five, CardColor.black)]),
          CardFace.none,
        ),
      );

      expect(
        () => engine.applyAction(
          state,
          PlayTurnAction(
            playerId: testOpponentLeftId,
            cards: [fxCard(CardFace.six, CardColor.red)],
          ),
        ),
        throwsA(isA<IllegalActionException>()),
      );
    });

    test('rejects actions when round is already complete', () {
      final engine = GameEngineImpl();
      final state = fxState(phase: GamePhase.play);
      state.scoreTracker.finalizeRound({
        for (final player in testPlayers) player.id: const <Card>[],
      });

      expect(
        () =>
            engine.applyAction(state, const PassAction(playerId: testHumanId)),
        throwsA(isA<IllegalActionException>()),
      );
    });

    test('blocks actions until human schupf receipts are acknowledged', () {
      final engine = GameEngineImpl();
      final state = fxState(phase: GamePhase.play);
      state.schupfReceipts[testHumanId] = [
        SchupfReceipt(
          card: fxCard(CardFace.five, CardColor.red),
          fromPlayerId: testOpponentLeftId,
          direction: SchupfDirection.left,
        ),
      ];

      expect(
        () =>
            engine.applyAction(state, const PassAction(playerId: testHumanId)),
        throwsA(isA<IllegalActionException>()),
      );

      engine.applyAction(
        state,
        const AcknowledgeSchupfAction(playerId: testHumanId),
      );
      expect(state.schupfReceipts.containsKey(testHumanId), isFalse);
    });

    test('allows out-of-turn bomb interruption', () {
      final engine = GameEngineImpl();
      final state = fxState(
        phase: GamePhase.play,
        deck: DeckState(
          TichuTurn(TurnType.single, [fxCard(CardFace.five, CardColor.black)]),
          CardFace.none,
        ),
        hands: {
          testHumanId: [fxCard(CardFace.nine, CardColor.red)],
          testOpponentLeftId: [
            fxCard(CardFace.two, CardColor.red),
            fxCard(CardFace.two, CardColor.blue),
            fxCard(CardFace.two, CardColor.green),
            fxCard(CardFace.two, CardColor.black),
          ],
          testOpponentPartnerId: [fxCard(CardFace.seven, CardColor.red)],
          testOpponentRightId: [fxCard(CardFace.eight, CardColor.red)],
        },
      );

      engine.applyAction(
        state,
        PlayTurnAction(
          playerId: testOpponentLeftId,
          cards: [
            fxCard(CardFace.two, CardColor.red),
            fxCard(CardFace.two, CardColor.blue),
            fxCard(CardFace.two, CardColor.green),
            fxCard(CardFace.two, CardColor.black),
          ],
        ),
      );

      expect(state.lastPlayedBy, testOpponentLeftId);
      expect(state.lastPlayedTurn?.type, TurnType.bomb);
    });
  });

  test('round log records plays and passes with the trick they answered', () {
    final engine = GameEngineImpl();
    final state = fxState(
      phase: GamePhase.play,
      hands: {
        testHumanId: [
          fxCard(CardFace.nine, CardColor.red),
          fxCard(CardFace.two, CardColor.red),
        ],
        testOpponentLeftId: [
          fxCard(CardFace.three, CardColor.red),
          fxCard(CardFace.four, CardColor.red),
        ],
        testOpponentPartnerId: [fxCard(CardFace.king, CardColor.red)],
        testOpponentRightId: [fxCard(CardFace.five, CardColor.red)],
      },
    );
    engine.applyAction(
      state,
      PlayTurnAction(
        playerId: testHumanId,
        cards: [fxCard(CardFace.nine, CardColor.red)],
      ),
    );
    engine.applyAction(state, const PassAction(playerId: testOpponentLeftId));

    expect(state.roundLog, hasLength(2));
    final lead = state.roundLog[0];
    expect(lead.playerId, testHumanId);
    expect(lead.isPass, isFalse);
    expect(lead.trickWinner, '');
    final pass = state.roundLog[1];
    expect(pass.playerId, testOpponentLeftId);
    expect(pass.isPass, isTrue);
    expect(pass.trickType, TurnType.single);
    expect(pass.trickValue, 9);
    expect(pass.trickWinner, testHumanId);
    // Snapshots carry the log; copies are independent.
    expect(engine.buildSnapshot(state).roundLog, hasLength(2));
    final copy = state.copy();
    engine.applyAction(copy, const PassAction(playerId: testOpponentPartnerId));
    expect(copy.roundLog, hasLength(3));
    expect(state.roundLog, hasLength(2));
  });
}
