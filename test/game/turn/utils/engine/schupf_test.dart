import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/engine_state.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/engine/schupf.dart';

import '../../../../utils/test_game_fixtures.dart';

Card _card(final CardFace face, final CardColor color) => Card(face, color);

GameEngineState _buildState() {
  final state = GameEngineState(
    gameId: 'g1',
    players: testPlayers,
    hands: {
      testHumanId: [
        _card(CardFace.mahJong, CardColor.special),
        _card(CardFace.two, CardColor.red),
        _card(CardFace.three, CardColor.red),
        _card(CardFace.four, CardColor.red),
      ],
      testOpponentLeftId: [
        _card(CardFace.five, CardColor.red),
        _card(CardFace.six, CardColor.red),
        _card(CardFace.seven, CardColor.red),
        _card(CardFace.eight, CardColor.red),
      ],
      testOpponentPartnerId: [
        _card(CardFace.nine, CardColor.red),
        _card(CardFace.ten, CardColor.red),
        _card(CardFace.jack, CardColor.red),
        _card(CardFace.queen, CardColor.red),
      ],
      testOpponentRightId: [
        _card(CardFace.king, CardColor.red),
        _card(CardFace.ace, CardColor.red),
        _card(CardFace.two, CardColor.blue),
        _card(CardFace.three, CardColor.blue),
      ],
    },
    reservedHands: {for (final player in testPlayers) player.id: <Card>[]},
    deck: DeckState(TichuTurn(TurnType.empty, const []), CardFace.ten),
    currentPlayerIndex: 1,
    scoreTracker: LocalScoreTracker(),
    phase: GamePhase.schupf,
  );
  state.scoreTracker.startNewRound(testPlayers);
  return state;
}

SchupfAction _firstThree(final String playerId, final List<Card> hand) =>
    SchupfAction(
      playerId: playerId,
      toLeft: hand[0],
      toPartner: hand[1],
      toRight: hand[2],
    );

void main() {
  group('applySchupfSelection', () {
    test('ignores duplicate selection from same player', () {
      final state = _buildState();
      final hand = state.hands[testHumanId]!;

      applySchupfSelection(state, _firstThree(testHumanId, hand));
      applySchupfSelection(
        state,
        SchupfAction(
          playerId: testHumanId,
          toLeft: hand.last,
          toPartner: hand.last,
          toRight: hand.last,
        ),
      );

      expect(state.schupfSelections, hasLength(1));
    });

    test('falls back to lowest cards when selected cards are invalid', () {
      final state = _buildState();

      applySchupfSelection(
        state,
        SchupfAction(
          playerId: testHumanId,
          toLeft: _card(CardFace.ace, CardColor.black),
          toPartner: _card(CardFace.king, CardColor.black),
          toRight: _card(CardFace.queen, CardColor.black),
        ),
      );

      final resolved = state.schupfSelections[testHumanId]!;
      expect(resolved.toLeft.face, CardFace.mahJong);
      expect(resolved.toPartner.face, CardFace.two);
      expect(resolved.toRight.face, CardFace.three);
    });

    test(
      'throws when hand has fewer than three cards and selection is invalid',
      () {
        final state = _buildState();
        state.hands[testHumanId] = [_card(CardFace.two, CardColor.red)];

        expect(
          () => applySchupfSelection(
            state,
            SchupfAction(
              playerId: testHumanId,
              toLeft: _card(CardFace.ace, CardColor.black),
              toPartner: _card(CardFace.king, CardColor.black),
              toRight: _card(CardFace.queen, CardColor.black),
            ),
          ),
          throwsStateError,
        );
      },
    );

    test('finalizes schupf after all players select', () {
      final state = _buildState();
      final initialHandLength = state.hands[testHumanId]!.length;

      for (final player in testPlayers) {
        applySchupfSelection(
          state,
          _firstThree(player.id, state.hands[player.id]!),
        );
      }

      expect(state.phase, GamePhase.play);
      expect(state.schupfSelections, isEmpty);
      expect(state.schupfReceipts.keys, hasLength(4));
      expect(state.schupfReceipts[testHumanId], hasLength(3));
      expect(state.schupfPendingAdditions[testHumanId], hasLength(3));
      expect(state.hands[testHumanId], hasLength(initialHandLength - 3));
      expect(state.currentPlayerIndex, 0);
      expect(state.deck.turn.type, TurnType.empty);
      expect(state.deck.wish, CardFace.ten);
      expect(state.lastPlayedBy, isNull);
      expect(state.lastPlayedTurn, isNull);
    });
  });

  group('schupf receipt helpers', () {
    test('pending receipt check is true only for humans with receipts', () {
      final state = _buildState();
      state.schupfReceipts[testHumanId] = [
        SchupfReceipt(
          card: _card(CardFace.five, CardColor.red),
          fromPlayerId: testOpponentLeftId,
          direction: SchupfDirection.left,
        ),
      ];
      state.schupfReceipts[testOpponentLeftId] = [
        SchupfReceipt(
          card: _card(CardFace.six, CardColor.red),
          fromPlayerId: testHumanId,
          direction: SchupfDirection.right,
        ),
      ];

      expect(hasPendingSchupfReceiptsForPlayer(state, testHumanId), isTrue);
      expect(
        hasPendingSchupfReceiptsForPlayer(state, testOpponentLeftId),
        isFalse,
      );
      expect(hasPendingSchupfReceiptsForPlayer(state, 'unknown'), isFalse);
      expect(hasPendingHumanSchupfReceipts(state), isTrue);
    });

    test('acknowledgement removes player receipts', () {
      final state = _buildState();
      final addedCard = _card(CardFace.king, CardColor.blue);
      state.schupfReceipts[testHumanId] = [
        SchupfReceipt(
          card: _card(CardFace.five, CardColor.red),
          fromPlayerId: testOpponentLeftId,
          direction: SchupfDirection.left,
        ),
      ];
      state.schupfPendingAdditions[testHumanId] = [addedCard];
      final previousLength = state.hands[testHumanId]!.length;

      applyAcknowledgeSchupf(
        state,
        const AcknowledgeSchupfAction(playerId: testHumanId),
      );

      expect(state.schupfReceipts.containsKey(testHumanId), isFalse);
      expect(state.schupfPendingAdditions.containsKey(testHumanId), isFalse);
      expect(state.hands[testHumanId], hasLength(previousLength + 1));
      expect(state.hands[testHumanId], contains(addedCard));
      expect(hasPendingHumanSchupfReceipts(state), isFalse);
    });
  });
}
