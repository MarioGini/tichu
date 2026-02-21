import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/engine_state.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/engine/turn_order.dart';

import '../../../../utils/test_game_fixtures.dart';

void main() {
  GameEngineState buildState() => GameEngineState(
    gameId: 'test-game',
    players: testPlayers,
    hands: {for (final player in testPlayers) player.id: <Card>[]},
    reservedHands: {for (final player in testPlayers) player.id: <Card>[]},
    deck: DeckState(TichuTurn(TurnType.empty, const []), CardFace.none),
    currentPlayerIndex: 0,
    scoreTracker: LocalScoreTracker(),
    phase: GamePhase.play,
  );

  group('turn order', () {
    test('advances by seat index 0 -> 1 -> 2 -> 3 -> 0', () {
      final state = buildState();

      expect(state.players[state.currentPlayerIndex].id, testHumanId);

      advanceToNextPlayer(state);
      expect(state.players[state.currentPlayerIndex].id, testOpponentLeftId);

      advanceToNextPlayer(state);
      expect(state.players[state.currentPlayerIndex].id, testOpponentPartnerId);

      advanceToNextPlayer(state);
      expect(state.players[state.currentPlayerIndex].id, testOpponentRightId);

      advanceToNextPlayer(state);
      expect(state.players[state.currentPlayerIndex].id, testHumanId);
    });

    test('skips finished players while advancing', () {
      final state = buildState();
      state.finishedPlayers.addAll({testOpponentLeftId, testOpponentPartnerId});

      final next = nextActiveIndex(state, 0);

      expect(state.players[next].id, testOpponentRightId);
    });
  });
}
