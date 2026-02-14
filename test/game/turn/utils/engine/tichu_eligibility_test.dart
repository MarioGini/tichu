import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';
import 'package:tichu/game/engine_state.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import '../../../../utils/test_game_fixtures.dart';

void main() {
  GameEngineState buildState({
    DeckState? deck,
    int currentPlayerIndex = 0,
    String? lastPlayedBy,
    List<Card>? currentTrickCards,
    List<Card>? humanHand,
  }) {
    final state = GameEngineState(
      gameId: 'test-game',
      players: testPlayers,
      hands: {
        testHumanId:
            humanHand ??
            [
              Card(CardFace.two, CardColor.red),
              Card(CardFace.three, CardColor.red),
            ],
        testOpponentLeftId: [Card(CardFace.five, CardColor.black)],
        testOpponentPartnerId: [Card(CardFace.six, CardColor.black)],
        testOpponentRightId: [Card(CardFace.seven, CardColor.black)],
      },
      reservedHands: {for (final player in testPlayers) player.id: <Card>[]},
      deck: deck ?? DeckState(TichuTurn(TurnType.empty, []), CardFace.none),
      currentPlayerIndex: currentPlayerIndex,
      scoreTracker: LocalScoreTracker(),
      phase: GamePhase.play,
    );
    state.scoreTracker.startNewRound(testPlayers);
    state.lastPlayedBy = lastPlayedBy;
    state.currentTrickCards.addAll(currentTrickCards ?? const <Card>[]);
    return state;
  }

  group('tichu eligibility', () {
    test('remains available after a pass before first played card', () {
      final engine = GameEngineImpl();
      final leadCard = Card(CardFace.five, CardColor.black);
      final state = buildState(
        deck: DeckState(TichuTurn(TurnType.single, [leadCard]), CardFace.none),
        currentPlayerIndex: 0,
        lastPlayedBy: testOpponentLeftId,
        currentTrickCards: [leadCard],
      );

      final beforePass = engine.buildPlayerSnapshot(
        engine.buildSnapshot(state),
        testHumanId,
      );
      expect(beforePass.canCallTichu, isTrue);

      engine.applyAction(state, const PassAction(playerId: testHumanId));

      final afterPass = engine.buildPlayerSnapshot(
        engine.buildSnapshot(state),
        testHumanId,
      );
      expect(afterPass.canCallTichu, isTrue);
    });

    test('becomes unavailable after player has played a card', () {
      final engine = GameEngineImpl();
      final firstCard = Card(CardFace.two, CardColor.red);
      final state = buildState(
        humanHand: [firstCard, Card(CardFace.three, CardColor.red)],
      );

      engine.applyAction(
        state,
        PlayTurnAction(playerId: testHumanId, cards: [firstCard]),
      );

      final snapshot = engine.buildPlayerSnapshot(
        engine.buildSnapshot(state),
        testHumanId,
      );
      expect(snapshot.canCallTichu, isFalse);
    });

    test('rejects CallTichuAction after first played card', () {
      final engine = GameEngineImpl();
      final firstCard = Card(CardFace.two, CardColor.red);
      final state = buildState(
        humanHand: [firstCard, Card(CardFace.three, CardColor.red)],
      );

      engine.applyAction(
        state,
        PlayTurnAction(playerId: testHumanId, cards: [firstCard]),
      );
      state.currentPlayerIndex = 0;

      expect(
        () => engine.applyAction(
          state,
          const CallTichuAction(playerId: testHumanId),
        ),
        throwsStateError,
      );
    });
  });
}
