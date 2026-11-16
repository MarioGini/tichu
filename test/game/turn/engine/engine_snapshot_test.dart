import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import '../../../utils/test_game_fixtures.dart';

import 'engine_test_fixtures.dart';

void main() {
  group('GameEngineImpl snapshots and pause logic', () {
    test('buildPlayerSnapshot hides opponents hands and exposes counts', () {
      final engine = GameEngineImpl();
      final state = fxState(phase: GamePhase.play);
      final snapshot = engine.buildSnapshot(state);
      final playerView = engine.buildPlayerSnapshot(snapshot, testHumanId);

      expect(playerView.hand, hasLength(1));
      expect(playerView.opponentCardCounts[testOpponentLeftId], 1);
      expect(playerView.opponentCardCounts[testOpponentPartnerId], 1);
      expect(playerView.opponentCardCounts[testOpponentRightId], 1);
    });

    test('shouldPauseForAutomatedOpponent follows guard conditions', () {
      final engine = GameEngineImpl();
      final state = fxState(
        phase: GamePhase.play,
        currentPlayerIndex: 2,
        hands: {
          testHumanId: [fxCard(CardFace.two, CardColor.red)],
          testOpponentLeftId: [fxCard(CardFace.three, CardColor.red)],
          testOpponentPartnerId: [fxCard(CardFace.four, CardColor.red)],
          testOpponentRightId: [fxCard(CardFace.five, CardColor.red)],
        },
      );

      expect(
        engine.shouldPauseForAutomatedOpponent(state, testOpponentLeftId),
        isTrue,
      );

      state.hands[testHumanId] = const <Card>[];
      expect(
        engine.shouldPauseForAutomatedOpponent(state, testOpponentLeftId),
        isFalse,
      );

      expect(
        engine.shouldPauseForAutomatedOpponent(state, testHumanId),
        isFalse,
      );
    });

    test('hasPendingHumanSchupfReceipts reflects human receipt state', () {
      final engine = GameEngineImpl();
      final state = fxState(phase: GamePhase.play);
      expect(engine.hasPendingHumanSchupfReceipts(state), isFalse);

      state.schupfReceipts[testHumanId] = [
        SchupfReceipt(
          card: fxCard(CardFace.five, CardColor.red),
          fromPlayerId: testOpponentLeftId,
          direction: SchupfDirection.left,
        ),
      ];

      expect(engine.hasPendingHumanSchupfReceipts(state), isTrue);
    });

    test('opponentIds returns only opposing seats', () {
      final engine = GameEngineImpl();
      final state = fxState(phase: GamePhase.play);

      expect(engine.opponentIds(state, testHumanId), [
        testOpponentLeftId,
        testOpponentRightId,
      ]);
    });
  });

  group('GameEngineImpl.startNewRound', () {
    test('resets round runtime state flags and pending data', () {
      final engine = GameEngineImpl();
      final state = fxState(phase: GamePhase.play);
      state.consecutivePasses = 2;
      state.lastPlayedBy = testHumanId;
      state.lastPlayedTurn = TichuTurn(TurnType.single, [
        fxCard(CardFace.five, CardColor.red),
      ]);
      state.pendingDragonGiveBy = testHumanId;
      state.pendingDragonGiveTargets.add(testOpponentLeftId);
      state.pendingDragonTrickCards.add(
        fxCard(CardFace.dragon, CardColor.special),
      );
      state.currentTrickCards.add(fxCard(CardFace.ten, CardColor.red));
      state.finishedPlayers.add(testHumanId);
      state.playersWhoPlayedCardsThisRound.add(testHumanId);

      engine.startNewRound(state);

      expect(state.phase, GamePhase.grandTichu);
      expect(state.consecutivePasses, 0);
      expect(state.lastPlayedBy, isNull);
      expect(state.lastPlayedTurn, isNull);
      expect(state.pendingDragonGiveBy, isNull);
      expect(state.pendingDragonGiveTargets, isEmpty);
      expect(state.pendingDragonTrickCards, isEmpty);
      expect(state.currentTrickCards, isEmpty);
      expect(state.finishedPlayers, isEmpty);
      expect(state.playersWhoPlayedCardsThisRound, isEmpty);
    });
  });
}
