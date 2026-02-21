import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/engine_state.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import '../../../utils/test_game_fixtures.dart';

Card _card(final CardFace face, final CardColor color) => Card(face, color);

GameEngineState _state({
  required final GamePhase phase,
  final int currentPlayerIndex = 0,
  final Map<String, List<Card>>? hands,
  final DeckState? deck,
}) {
  final state = GameEngineState(
    gameId: 'g1',
    players: testPlayers,
    hands:
        hands ??
        {
          testHumanId: [_card(CardFace.two, CardColor.red)],
          testOpponentLeftId: [_card(CardFace.three, CardColor.red)],
          testOpponentPartnerId: [_card(CardFace.four, CardColor.red)],
          testOpponentRightId: [_card(CardFace.five, CardColor.red)],
        },
    reservedHands: {for (final player in testPlayers) player.id: <Card>[]},
    deck: deck ?? DeckState(TichuTurn(TurnType.empty, const []), CardFace.none),
    currentPlayerIndex: currentPlayerIndex,
    scoreTracker: LocalScoreTracker(),
    phase: phase,
  );
  state.scoreTracker.startNewRound(testPlayers);
  return state;
}

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
      final state = _state(phase: GamePhase.grandTichu);

      expect(
        () =>
            engine.applyAction(state, const PassAction(playerId: testHumanId)),
        throwsStateError,
      );
    });

    test('rejects out-of-turn grand tichu decision', () {
      final engine = GameEngineImpl();
      final state = _state(phase: GamePhase.grandTichu);

      expect(
        () => engine.applyAction(
          state,
          const GrandTichuDecisionAction(
            playerId: testOpponentLeftId,
            call: false,
          ),
        ),
        throwsStateError,
      );
    });

    test('allows calling tichu during grand tichu phase', () {
      final engine = GameEngineImpl();
      final state = _state(phase: GamePhase.grandTichu);

      engine.applyAction(state, const CallTichuAction(playerId: testHumanId));

      expect(state.scoreTracker.state.tichuCalls[testHumanId], TichuCall.tichu);
      expect(state.grandTichuDecisions[testHumanId], isFalse);
      expect(state.currentPlayerIndex, 1);
    });

    test('disallows grand tichu if player already called tichu', () {
      final engine = GameEngineImpl();
      final state = _state(phase: GamePhase.grandTichu);

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
      final state = _state(phase: GamePhase.schupf);

      expect(
        () =>
            engine.applyAction(state, const PassAction(playerId: testHumanId)),
        throwsStateError,
      );
    });

    test('allows tichu call during schupf phase', () {
      final engine = GameEngineImpl();
      final state = _state(phase: GamePhase.schupf);

      engine.applyAction(state, const CallTichuAction(playerId: testHumanId));

      final tichuCall = state.scoreTracker.state.tichuCalls[testHumanId];
      expect(tichuCall, TichuCall.tichu);
    });

    test('blocks non dragon action while dragon give is pending', () {
      final engine = GameEngineImpl();
      final state = _state(phase: GamePhase.play);
      state.pendingDragonGiveBy = testOpponentLeftId;
      state.pendingDragonGiveTargets.addAll([
        testHumanId,
        testOpponentPartnerId,
      ]);

      expect(
        () =>
            engine.applyAction(state, const PassAction(playerId: testHumanId)),
        throwsStateError,
      );
    });

    test('rejects out-of-turn non-bomb play', () {
      final engine = GameEngineImpl();
      final state = _state(
        phase: GamePhase.play,
        deck: DeckState(
          TichuTurn(TurnType.single, [_card(CardFace.five, CardColor.black)]),
          CardFace.none,
        ),
      );

      expect(
        () => engine.applyAction(
          state,
          PlayTurnAction(
            playerId: testOpponentLeftId,
            cards: [_card(CardFace.six, CardColor.red)],
          ),
        ),
        throwsStateError,
      );
    });

    test('rejects actions when round is already complete', () {
      final engine = GameEngineImpl();
      final state = _state(phase: GamePhase.play);
      state.scoreTracker.finalizeRound({
        for (final player in testPlayers) player.id: const <Card>[],
      });

      expect(
        () =>
            engine.applyAction(state, const PassAction(playerId: testHumanId)),
        throwsStateError,
      );
    });

    test('blocks actions until human schupf receipts are acknowledged', () {
      final engine = GameEngineImpl();
      final state = _state(phase: GamePhase.play);
      state.schupfReceipts[testHumanId] = [
        SchupfReceipt(
          card: _card(CardFace.five, CardColor.red),
          fromPlayerId: testOpponentLeftId,
          direction: SchupfDirection.left,
        ),
      ];

      expect(
        () =>
            engine.applyAction(state, const PassAction(playerId: testHumanId)),
        throwsStateError,
      );

      engine.applyAction(
        state,
        const AcknowledgeSchupfAction(playerId: testHumanId),
      );
      expect(state.schupfReceipts.containsKey(testHumanId), isFalse);
    });

    test('allows out-of-turn bomb interruption', () {
      final engine = GameEngineImpl();
      final state = _state(
        phase: GamePhase.play,
        deck: DeckState(
          TichuTurn(TurnType.single, [_card(CardFace.five, CardColor.black)]),
          CardFace.none,
        ),
        hands: {
          testHumanId: [_card(CardFace.nine, CardColor.red)],
          testOpponentLeftId: [
            _card(CardFace.two, CardColor.red),
            _card(CardFace.two, CardColor.blue),
            _card(CardFace.two, CardColor.green),
            _card(CardFace.two, CardColor.black),
          ],
          testOpponentPartnerId: [_card(CardFace.seven, CardColor.red)],
          testOpponentRightId: [_card(CardFace.eight, CardColor.red)],
        },
      );

      engine.applyAction(
        state,
        PlayTurnAction(
          playerId: testOpponentLeftId,
          cards: [
            _card(CardFace.two, CardColor.red),
            _card(CardFace.two, CardColor.blue),
            _card(CardFace.two, CardColor.green),
            _card(CardFace.two, CardColor.black),
          ],
        ),
      );

      expect(state.lastPlayedBy, testOpponentLeftId);
      expect(state.lastPlayedTurn?.type, TurnType.bomb);
    });
  });

  group('GameEngineImpl snapshots and pause logic', () {
    test('buildPlayerSnapshot hides opponents hands and exposes counts', () {
      final engine = GameEngineImpl();
      final state = _state(phase: GamePhase.play);
      final snapshot = engine.buildSnapshot(state);
      final playerView = engine.buildPlayerSnapshot(snapshot, testHumanId);

      expect(playerView.hand, hasLength(1));
      expect(playerView.opponentCardCounts[testOpponentLeftId], 1);
      expect(playerView.opponentCardCounts[testOpponentPartnerId], 1);
      expect(playerView.opponentCardCounts[testOpponentRightId], 1);
    });

    test('shouldPauseForAutomatedOpponent follows guard conditions', () {
      final engine = GameEngineImpl();
      final state = _state(
        phase: GamePhase.play,
        currentPlayerIndex: 2,
        hands: {
          testHumanId: [_card(CardFace.two, CardColor.red)],
          testOpponentLeftId: [_card(CardFace.three, CardColor.red)],
          testOpponentPartnerId: [_card(CardFace.four, CardColor.red)],
          testOpponentRightId: [_card(CardFace.five, CardColor.red)],
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
      final state = _state(phase: GamePhase.play);
      expect(engine.hasPendingHumanSchupfReceipts(state), isFalse);

      state.schupfReceipts[testHumanId] = [
        SchupfReceipt(
          card: _card(CardFace.five, CardColor.red),
          fromPlayerId: testOpponentLeftId,
          direction: SchupfDirection.left,
        ),
      ];

      expect(engine.hasPendingHumanSchupfReceipts(state), isTrue);
    });

    test('opponentIds returns only opposing seats', () {
      final engine = GameEngineImpl();
      final state = _state(phase: GamePhase.play);

      expect(engine.opponentIds(state, testHumanId), [
        testOpponentLeftId,
        testOpponentRightId,
      ]);
    });
  });

  group('GameEngineImpl.startNewRound', () {
    test('resets round runtime state flags and pending data', () {
      final engine = GameEngineImpl();
      final state = _state(phase: GamePhase.play);
      state.consecutivePasses = 2;
      state.lastPlayedBy = testHumanId;
      state.lastPlayedTurn = TichuTurn(TurnType.single, [
        _card(CardFace.five, CardColor.red),
      ]);
      state.pendingDragonGiveBy = testHumanId;
      state.pendingDragonGiveTargets.add(testOpponentLeftId);
      state.pendingDragonTrickCards.add(
        _card(CardFace.dragon, CardColor.special),
      );
      state.currentTrickCards.add(_card(CardFace.ten, CardColor.red));
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
