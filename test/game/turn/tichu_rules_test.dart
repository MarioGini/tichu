import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/engine_state.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/engine/trick_resolution.dart';

import '../../utils/test_game_fixtures.dart';

void main() {
  GameEngineState buildState() =>
      GameEngineState(
          gameId: 'test-game',
          players: testPlayers,
          hands: {for (final player in testPlayers) player.id: <Card>[]},
          reservedHands: {
            for (final player in testPlayers) player.id: <Card>[],
          },
          deck: DeckState(
            TichuTurn(TurnType.single, [
              Card(CardFace.dragon, CardColor.special),
            ]),
            CardFace.none,
          ),
          currentPlayerIndex: 1,
          scoreTracker: LocalScoreTracker(),
          phase: GamePhase.play,
        )
        ..lastPlayedBy = testHumanId
        ..lastPlayedTurn = TichuTurn(TurnType.single, [
          Card(CardFace.dragon, CardColor.special),
        ])
        ..currentTrickCards.add(Card(CardFace.dragon, CardColor.special));

  group('trick completion on lead return', () {
    test('awards trick when pass returns turn to active trick leader', () {
      final state = buildState();
      state.finishedPlayers.addAll({
        testOpponentPartnerId,
        testOpponentRightId,
      });

      applyPassAction(state, const PassAction(playerId: testOpponentLeftId));

      expect(state.pendingDragonGiveBy, testHumanId);
      expect(state.pendingDragonGiveTargets, contains(testOpponentLeftId));
      expect(state.currentTrickCards, isEmpty);
      expect(state.deck.turn.type, TurnType.empty);
      expect(state.currentPlayerIndex, 0);
      expect(state.consecutivePasses, 0);
    });

    test(
      'awards trick when leader is finished and turn returns to next active',
      () {
        final state = buildState();
        state.finishedPlayers.addAll({
          testHumanId,
          testOpponentPartnerId,
          testOpponentRightId,
        });

        applyPassAction(state, const PassAction(playerId: testOpponentLeftId));

        expect(state.pendingDragonGiveBy, testHumanId);
        expect(state.pendingDragonGiveTargets, contains(testOpponentLeftId));
        expect(state.currentTrickCards, isEmpty);
        expect(state.deck.turn.type, TurnType.empty);
        expect(state.currentPlayerIndex, 1);
        expect(state.consecutivePasses, 0);
      },
    );
  });
}
