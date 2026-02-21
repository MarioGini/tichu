import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/engine_state.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/turn_handler.dart';
import 'package:tichu/game/turn/utils/engine/trick_resolution.dart';

import '../../../../utils/test_game_fixtures.dart';

Card _card(final CardFace face, final CardColor color) => Card(face, color);

class _FakeTurnHandler extends TurnHandler {
  final DeckState Function(DeckState, List<Card>, CardFace) builder;

  _FakeTurnHandler(this.builder);

  @override
  DeckState handleTurn(
    final DeckState currentDeck,
    final List<Card> selectedCards,
    final CardFace inputWish, {
    final List<Card>? hand,
  }) => builder(currentDeck, selectedCards, inputWish);
}

GameEngineState _buildState({
  final DeckState? deck,
  final int currentPlayerIndex = 0,
  final List<Card>? hand,
}) {
  final state = GameEngineState(
    gameId: 'g1',
    players: testPlayers,
    hands: {
      testHumanId:
          hand ??
          [
            _card(CardFace.two, CardColor.red),
            _card(CardFace.three, CardColor.red),
          ],
      testOpponentLeftId: [_card(CardFace.five, CardColor.blue)],
      testOpponentPartnerId: [_card(CardFace.six, CardColor.blue)],
      testOpponentRightId: [_card(CardFace.seven, CardColor.blue)],
    },
    reservedHands: {for (final player in testPlayers) player.id: <Card>[]},
    deck: deck ?? DeckState(TichuTurn(TurnType.empty, const []), CardFace.none),
    currentPlayerIndex: currentPlayerIndex,
    scoreTracker: LocalScoreTracker(),
    phase: GamePhase.play,
  );
  state.scoreTracker.startNewRound(testPlayers);
  return state;
}

void main() {
  group('applyPlayAction', () {
    test('throws when cards are not in hand', () {
      final state = _buildState();
      final handler = _FakeTurnHandler(
        (final deck, final cards, final wish) =>
            DeckState(TichuTurn(TurnType.single, cards), wish),
      );

      expect(
        () => applyPlayAction(
          state,
          PlayTurnAction(
            playerId: testHumanId,
            cards: [_card(CardFace.ace, CardColor.black)],
          ),
          handler,
        ),
        throwsStateError,
      );
    });

    test('throws when turn handler returns invalid turn', () {
      final state = _buildState();
      final handler = _FakeTurnHandler(
        (final deck, final cards, final wish) => DeckState.Invalid(),
      );

      expect(
        () => applyPlayAction(
          state,
          PlayTurnAction(
            playerId: testHumanId,
            cards: [state.hands[testHumanId]!.first],
          ),
          handler,
        ),
        throwsStateError,
      );
    });

    test('dog play passes lead to partner and clears trick', () {
      final dog = _card(CardFace.dog, CardColor.special);
      final state = _buildState(
        hand: [dog, _card(CardFace.five, CardColor.red)],
      );
      final handler = _FakeTurnHandler(
        (final deck, final cards, final wish) =>
            DeckState(TichuTurn(TurnType.dog, cards), wish),
      );

      applyPlayAction(
        state,
        PlayTurnAction(playerId: testHumanId, cards: [dog]),
        handler,
      );

      expect(state.currentPlayerIndex, 2);
      expect(state.lastPlayedBy, isNull);
      expect(state.deck.turn.type, TurnType.empty);
      expect(state.currentTrickCards, isEmpty);
    });
  });

  group('applyPassAction', () {
    test('throws on empty trick', () {
      final state = _buildState();

      expect(
        () => applyPassAction(state, const PassAction(playerId: testHumanId)),
        throwsStateError,
      );
    });

    test('throws when wish must be fulfilled', () {
      final state = _buildState(
        hand: [
          _card(CardFace.five, CardColor.red),
          _card(CardFace.two, CardColor.red),
        ],
        deck: DeckState(
          TichuTurn(TurnType.single, [_card(CardFace.four, CardColor.black)]),
          CardFace.five,
        ),
      );
      state.lastPlayedBy = testOpponentLeftId;

      expect(
        () => applyPassAction(state, const PassAction(playerId: testHumanId)),
        throwsStateError,
      );
    });

    test('awards trick when lead returns to winner', () {
      final lead = _card(CardFace.ten, CardColor.red);
      final state = _buildState(
        deck: DeckState(TichuTurn(TurnType.single, [lead]), CardFace.none),
      );
      state.lastPlayedBy = testOpponentLeftId;
      state.currentTrickCards.addAll([
        lead,
        _card(CardFace.five, CardColor.red),
      ]);
      state.currentPlayerIndex = 0;

      applyPassAction(state, const PassAction(playerId: testHumanId));

      expect(state.currentTrickCards, isEmpty);
      expect(state.deck.turn.type, TurnType.empty);
      expect(state.consecutivePasses, 0);
      expect(
        state.scoreTracker.state.playerRoundPoints[testOpponentLeftId],
        15,
      );
    });
  });

  group('dragon trick handling', () {
    test('dragonWonTrick true only for single dragon turn', () {
      final state = _buildState();
      expect(dragonWonTrick(state), isFalse);

      state.lastPlayedTurn = TichuTurn(TurnType.pair, [
        _card(CardFace.dragon, CardColor.special),
        _card(CardFace.dragon, CardColor.special),
      ]);
      expect(dragonWonTrick(state), isFalse);

      state.lastPlayedTurn = TichuTurn(TurnType.single, [
        _card(CardFace.dragon, CardColor.special),
      ]);
      expect(dragonWonTrick(state), isTrue);
    });

    test('maybeAwardTrick creates pending dragon give for opponents', () {
      final state = _buildState();
      state.lastPlayedTurn = TichuTurn(TurnType.single, [
        _card(CardFace.dragon, CardColor.special),
      ]);

      final awarded = maybeAwardTrick(state, testHumanId, [
        _card(CardFace.dragon, CardColor.special),
      ]);

      expect(awarded, isFalse);
      expect(state.pendingDragonGiveBy, testHumanId);
      expect(state.pendingDragonGiveTargets, [
        testOpponentLeftId,
        testOpponentRightId,
      ]);
      expect(state.pendingDragonTrickCards, hasLength(1));
    });

    test('applyGiveDragonAction validates and records trick', () {
      final state = _buildState();
      expect(
        () => applyGiveDragonAction(
          state,
          const GiveDragonAction(
            playerId: testHumanId,
            targetPlayerId: testOpponentLeftId,
          ),
        ),
        throwsStateError,
      );

      state.pendingDragonGiveBy = testHumanId;
      state.pendingDragonGiveTargets.addAll([
        testOpponentLeftId,
        testOpponentRightId,
      ]);
      state.pendingDragonTrickCards.addAll([
        _card(CardFace.dragon, CardColor.special),
      ]);

      expect(
        () => applyGiveDragonAction(
          state,
          const GiveDragonAction(
            playerId: testHumanId,
            targetPlayerId: testOpponentPartnerId,
          ),
        ),
        throwsStateError,
      );

      applyGiveDragonAction(
        state,
        const GiveDragonAction(
          playerId: testHumanId,
          targetPlayerId: testOpponentLeftId,
        ),
      );

      expect(state.pendingDragonGiveBy, isNull);
      expect(state.pendingDragonGiveTargets, isEmpty);
      expect(state.pendingDragonTrickCards, isEmpty);
      expect(state.lastDragonGiveBy, testHumanId);
      expect(state.lastDragonGiveTo, testOpponentLeftId);
      expect(
        state.scoreTracker.state.playerRoundPoints[testOpponentLeftId],
        25,
      );
    });

    test(
      'finalizeRoundIfComplete finalizes when three players are finished',
      () {
        final state = _buildState();
        state.finishedPlayers.addAll([
          testHumanId,
          testOpponentLeftId,
          testOpponentPartnerId,
        ]);

        finalizeRoundIfComplete(state);

        expect(state.scoreTracker.state.roundComplete, isTrue);
      },
    );

    test('finalizeRoundIfComplete finalizes immediately on match finish', () {
      final state = _buildState();
      state.finishedPlayers.addAll([testHumanId, testOpponentPartnerId]);
      state.scoreTracker.recordPlayerFinished(testHumanId, const <Card>[]);
      state.scoreTracker.recordPlayerFinished(
        testOpponentPartnerId,
        const <Card>[],
      );

      finalizeRoundIfComplete(state);

      expect(state.scoreTracker.state.roundComplete, isTrue);
      expect(
        state.scoreTracker.state.rounds.last.roundEndType,
        RoundEndType.match,
      );
      expect(state.scoreTracker.state.teamOneRound, 200);
      expect(state.scoreTracker.state.teamTwoRound, 0);
      expect(state.scoreTracker.state.rounds.last.teamOneCardPoints, 0);
      expect(state.scoreTracker.state.rounds.last.teamTwoCardPoints, 0);
    });
  });
}
