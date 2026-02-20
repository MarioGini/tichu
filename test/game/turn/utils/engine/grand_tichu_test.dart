import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/engine_state.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/engine/grand_tichu.dart';

import '../../../../utils/test_game_fixtures.dart';

GameEngineState _buildState() {
  final state = GameEngineState(
    gameId: 'g1',
    players: testPlayers,
    hands: {
      for (final player in testPlayers)
        player.id: [Card(CardFace.two, CardColor.red)],
    },
    reservedHands: {
      for (final player in testPlayers)
        player.id: [Card(CardFace.three, CardColor.blue)],
    },
    deck: DeckState(TichuTurn(TurnType.empty, const []), CardFace.none),
    currentPlayerIndex: 0,
    scoreTracker: LocalScoreTracker(),
    phase: GamePhase.grandTichu,
  );
  state.scoreTracker.startNewRound(testPlayers);
  return state;
}

void main() {
  group('applyGrandTichuDecision', () {
    test('records decision only once per player', () {
      final state = _buildState();

      applyGrandTichuDecision(
        state,
        const GrandTichuDecisionAction(playerId: testHumanId, call: true),
      );
      applyGrandTichuDecision(
        state,
        const GrandTichuDecisionAction(playerId: testHumanId, call: false),
      );

      expect(state.grandTichuDecisions[testHumanId], isTrue);
      expect(
        state.scoreTracker.state.tichuCalls[testHumanId],
        TichuCall.grandTichu,
      );
    });

    test('moves reserved cards into hands after all players decided', () {
      final state = _buildState();

      for (final player in testPlayers) {
        applyGrandTichuDecision(
          state,
          GrandTichuDecisionAction(playerId: player.id, call: false),
        );
      }

      for (final player in testPlayers) {
        expect(state.hands[player.id], hasLength(2));
      }
      expect(state.reservedHands, isEmpty);
      expect(state.phase, GamePhase.schupf);
      expect(state.schupfSelections, isEmpty);
    });

    test('advances current player after each decision', () {
      final state = _buildState();
      expect(state.currentPlayerIndex, 0);

      applyGrandTichuDecision(
        state,
        const GrandTichuDecisionAction(playerId: testHumanId, call: false),
      );

      expect(state.currentPlayerIndex, 1);
    });

    test('suppresses grand tichu when teammate already called', () {
      final state = _buildState();

      applyGrandTichuDecision(
        state,
        const GrandTichuDecisionAction(playerId: testHumanId, call: true),
      );
      applyGrandTichuDecision(
        state,
        const GrandTichuDecisionAction(
          playerId: testOpponentPartnerId,
          call: true,
        ),
      );

      expect(state.grandTichuDecisions[testHumanId], isTrue);
      expect(state.grandTichuDecisions[testOpponentPartnerId], isFalse);
      expect(
        state.scoreTracker.state.tichuCalls[testOpponentPartnerId],
        isNull,
      );
    });
  });
}
