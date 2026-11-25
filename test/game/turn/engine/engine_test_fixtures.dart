import 'package:tichu/game/engine_state.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import '../../../utils/test_game_fixtures.dart';

Card fxCard(CardFace face, CardColor color) => Card(face, color);

GameEngineState fxState({
  required GamePhase phase,
  int currentPlayerIndex = 0,
  Map<String, List<Card>>? hands,
  DeckState? deck,
}) {
  final state = GameEngineState(
    gameId: 'g1',
    players: testPlayers,
    hands:
        hands ??
        {
          testHumanId: [fxCard(CardFace.two, CardColor.red)],
          testOpponentLeftId: [fxCard(CardFace.three, CardColor.red)],
          testOpponentPartnerId: [fxCard(CardFace.four, CardColor.red)],
          testOpponentRightId: [fxCard(CardFace.five, CardColor.red)],
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
