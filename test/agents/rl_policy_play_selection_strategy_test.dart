import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/play_selection_strategy.dart';
import 'package:tichu/agents/rl_codec.dart';
import 'package:tichu/agents/rl_policy_play_selection_strategy.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'ai_test_fixtures.dart';

class _FirstPlayFallback implements PlaySelectionStrategy {
  const _FirstPlayFallback();

  @override
  TichuTurn selectPlay(
    final GameSnapshot snapshot,
    final List<TichuTurn> plays,
    final DeckState deck,
    final List<Card> hand,
  ) => plays.first;
}

void main() {
  group('RlPolicyPlaySelectionStrategy', () {
    test('uses policy value when state/action key matches', () {
      final hand = [
        Card(CardFace.five, CardColor.red),
        Card(CardFace.six, CardColor.red),
        Card(CardFace.six, CardColor.blue),
        Card(CardFace.king, CardColor.red),
      ];
      final single = TichuTurn(TurnType.single, [
        Card(CardFace.five, CardColor.red),
      ]);
      final pair = TichuTurn(TurnType.pair, [
        Card(CardFace.six, CardColor.red),
        Card(CardFace.six, CardColor.blue),
      ]);
      final snapshot = aiSnapshot(myHand: hand, currentPlayerId: aiTestSelfId);
      final stateKey = buildRlStateKey(
        snapshot: snapshot,
        playerId: aiTestSelfId,
      );

      final policy = RlPolicyTable({
        stateKey: {
          encodeRlPlayActionKeyFromTurn(single): 1,
          encodeRlPlayActionKeyFromTurn(pair): 5,
        },
      });

      final strategy = RlPolicyPlaySelectionStrategy(
        playerId: aiTestSelfId,
        policy: policy,
        fallback: const _FirstPlayFallback(),
      );

      final selected = strategy.selectPlay(
        snapshot,
        [single, pair],
        aiEmptyDeck(),
        hand,
      );

      expect(selected.type, TurnType.pair);
    });

    test('falls back when no policy match exists', () {
      final hand = [
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.king, CardColor.red),
      ];
      final first = TichuTurn(TurnType.single, [
        Card(CardFace.five, CardColor.blue),
      ]);
      final second = TichuTurn(TurnType.single, [
        Card(CardFace.king, CardColor.red),
      ]);

      const strategy = RlPolicyPlaySelectionStrategy(
        playerId: aiTestSelfId,
        policy: RlPolicyTable.empty(),
        fallback: _FirstPlayFallback(),
      );

      final selected = strategy.selectPlay(
        aiSnapshot(myHand: hand, currentPlayerId: aiTestSelfId),
        [first, second],
        aiEmptyDeck(),
        hand,
      );

      expect(selected, same(first));
    });

    test('ignores illegal policy-favored candidate turn', () {
      final legal = TichuTurn(TurnType.single, [
        Card(CardFace.five, CardColor.blue),
      ]);
      final illegal = TichuTurn(TurnType.pair, [
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.ace, CardColor.blue),
      ]);

      final snapshot = aiSnapshot(
        myHand: aiDefaultHand(),
        currentPlayerId: aiTestSelfId,
      );
      final stateKey = buildRlStateKey(
        snapshot: snapshot,
        playerId: aiTestSelfId,
      );

      final policy = RlPolicyTable({
        stateKey: {
          encodeRlPlayActionKeyFromTurn(legal): 1,
          encodeRlPlayActionKeyFromTurn(illegal): 100,
        },
      });

      final strategy = RlPolicyPlaySelectionStrategy(
        playerId: aiTestSelfId,
        policy: policy,
        fallback: const _FirstPlayFallback(),
      );

      final selected = strategy.selectPlay(
        snapshot,
        [illegal, legal],
        aiEmptyDeck(),
        aiDefaultHand(),
      );

      expect(selected, equals(legal));
    });

    test('fallback receives only legal candidates', () {
      final illegal = TichuTurn(TurnType.pair, [
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.ace, CardColor.blue),
      ]);
      final legal = TichuTurn(TurnType.single, [
        Card(CardFace.five, CardColor.blue),
      ]);

      const strategy = RlPolicyPlaySelectionStrategy(
        playerId: aiTestSelfId,
        policy: RlPolicyTable.empty(),
        fallback: _FirstPlayFallback(),
      );

      final selected = strategy.selectPlay(
        aiSnapshot(myHand: aiDefaultHand(), currentPlayerId: aiTestSelfId),
        [illegal, legal],
        aiEmptyDeck(),
        aiDefaultHand(),
      );

      expect(selected, equals(legal));
    });

    test('uses coarse state values when exact state has no match', () {
      final hand = [
        Card(CardFace.five, CardColor.red),
        Card(CardFace.six, CardColor.red),
        Card(CardFace.six, CardColor.blue),
      ];
      final single = TichuTurn(TurnType.single, [
        Card(CardFace.five, CardColor.red),
      ]);
      final pair = TichuTurn(TurnType.pair, [
        Card(CardFace.six, CardColor.red),
        Card(CardFace.six, CardColor.blue),
      ]);

      final snapshot = aiSnapshot(myHand: hand, currentPlayerId: aiTestSelfId);
      final coarseStateKey = buildRlCoarseStateKey(
        snapshot: snapshot,
        playerId: aiTestSelfId,
      );

      final policy = RlPolicyTable(
        const {},
        coarseStateActionValues: {
          coarseStateKey: {
            encodeRlPlayActionKeyFromTurn(single): 1,
            encodeRlPlayActionKeyFromTurn(pair): 10,
          },
        },
      );

      final strategy = RlPolicyPlaySelectionStrategy(
        playerId: aiTestSelfId,
        policy: policy,
        fallback: const _FirstPlayFallback(),
      );

      final selected = strategy.selectPlay(
        snapshot,
        [single, pair],
        aiEmptyDeck(),
        hand,
      );
      expect(selected, equals(pair));
    });

    test('parses policy from state_action_values json map', () {
      final parsed = RlPolicyTable.fromJsonObject({
        'state_action_values': {
          's1': {'a1': 1.5, 'a2': 2},
        },
        'coarse_state_action_values': {
          'c1': {'x1': 3.5},
        },
      });

      expect(parsed.isEmpty, isFalse);
      expect(parsed.valuesForState('s1')?['a1'], 1.5);
      expect(parsed.valuesForState('s1')?['a2'], 2.0);
      expect(parsed.valuesForCoarseState('c1')?['x1'], 3.5);
    });
  });
}
