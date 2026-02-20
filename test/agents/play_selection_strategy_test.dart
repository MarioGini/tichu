import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/play_selection_strategy.dart';
import 'package:tichu/agents/turn_scorer.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'ai_test_fixtures.dart';

class _StubScorer extends TurnScorer {
  _StubScorer(this.scores);

  final Map<TurnType, double> scores;

  @override
  double scoreTurn(
    final GameSnapshot snapshot,
    final String playerId,
    final TichuTurn play,
    final DeckState deck,
    final List<Card> hand,
  ) => scores[play.type] ?? 0;
}

void main() {
  group('DefaultPlaySelectionStrategy', () {
    test('selects highest-scoring play', () {
      final strategy = DefaultPlaySelectionStrategy(
        turnScorer: _StubScorer({TurnType.single: 1, TurnType.pair: 5}),
      );
      final plays = [
        TichuTurn(TurnType.single, [Card(CardFace.five, CardColor.red)]),
        TichuTurn(TurnType.pair, [
          Card(CardFace.six, CardColor.red),
          Card(CardFace.six, CardColor.blue),
        ]),
      ];

      final selected = strategy.selectPlay(
        aiSnapshot(myHand: aiDefaultHand(), currentPlayerId: aiTestSelfId),
        plays,
        aiEmptyDeck(),
        aiDefaultHand(),
      );

      expect(selected.type, TurnType.pair);
    });

    test('breaks score ties by lower value', () {
      final strategy = DefaultPlaySelectionStrategy(
        turnScorer: _StubScorer({TurnType.single: 5}),
      );
      final low = TichuTurn(TurnType.single, [
        Card(CardFace.five, CardColor.red),
      ]);
      final high = TichuTurn(TurnType.single, [
        Card(CardFace.king, CardColor.red),
      ]);

      final selected = strategy.selectPlay(
        aiSnapshot(myHand: aiDefaultHand(), currentPlayerId: aiTestSelfId),
        [high, low],
        aiEmptyDeck(),
        aiDefaultHand(),
      );

      expect(selected.value, low.value);
    });

    test('falls back to first play when scorer yields no comparable score', () {
      final strategy = DefaultPlaySelectionStrategy(
        turnScorer: _StubScorer({TurnType.single: double.nan}),
      );
      final first = TichuTurn(TurnType.single, [
        Card(CardFace.five, CardColor.red),
      ]);
      final second = TichuTurn(TurnType.single, [
        Card(CardFace.king, CardColor.red),
      ]);

      final selected = strategy.selectPlay(
        aiSnapshot(myHand: aiDefaultHand(), currentPlayerId: aiTestSelfId),
        [first, second],
        aiEmptyDeck(),
        aiDefaultHand(),
      );

      expect(selected, same(first));
    });
  });
}
