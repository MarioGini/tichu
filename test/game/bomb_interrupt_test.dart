import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/heuristic_options.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/agent_decisions.dart';
import 'package:tichu/game/engine_state.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import '../utils/test_game_fixtures.dart';
import 'turn/engine/engine_test_fixtures.dart';

/// Human (seat 0) is to move on a single five played by [winner]; the left
/// opponent (seat 1) holds four twos.
({GameEngineImpl engine, GameEngineState state}) _setup({
  final String winner = testOpponentRightId,
  final int winnerCards = 1,
}) {
  final engine = GameEngineImpl();
  final state = fxState(
    phase: GamePhase.play,
    deck: DeckState(
      TichuTurn(TurnType.single, [fxCard(CardFace.five, CardColor.black)]),
      CardFace.none,
    ),
    hands: {
      testHumanId: [
        fxCard(CardFace.nine, CardColor.red),
        fxCard(CardFace.ten, CardColor.red),
      ],
      testOpponentLeftId: [
        fxCard(CardFace.two, CardColor.red),
        fxCard(CardFace.two, CardColor.blue),
        fxCard(CardFace.two, CardColor.green),
        fxCard(CardFace.two, CardColor.black),
        fxCard(CardFace.king, CardColor.black),
      ],
      testOpponentPartnerId: [fxCard(CardFace.seven, CardColor.red)],
      testOpponentRightId: [
        for (var i = 0; i < winnerCards; i++)
          fxCard(CardFace.eight, CardColor.values[i % 4]),
      ],
    },
  );
  state.lastPlayedBy = winner;
  return (engine: engine, state: state);
}

void main() {
  group('out-of-turn bombs', () {
    test('a player with a beating bomb is asked before the player to move', () {
      final (:engine, :state) = _setup();
      final request = AgentDecisions.next(engine, state);
      expect(request, isA<BombInterruptRequest>());
      expect(request!.playerId, testOpponentLeftId);
      expect((request as BombInterruptRequest).bombs, hasLength(1));
    });

    test('a decline holds until the next play or pass', () {
      final (:engine, :state) = _setup();
      engine.applyAction(
        state,
        const DeclineBombAction(playerId: testOpponentLeftId),
      );
      final request = AgentDecisions.next(engine, state);
      expect(request, isA<TurnRequest>());
      expect(request!.playerId, testHumanId);

      engine.applyAction(state, const PassAction(playerId: testHumanId));
      // The left player is now to move: no interrupt for them.
      expect(AgentDecisions.next(engine, state), isA<TurnRequest>());
    });

    test('the copy of a state keeps the declines', () {
      final (:engine, :state) = _setup();
      engine.applyAction(
        state,
        const DeclineBombAction(playerId: testOpponentLeftId),
      );
      expect(AgentDecisions.next(engine, state.copy()), isA<TurnRequest>());
    });

    test('no interrupts on an empty table or when switched off', () {
      final (:engine, :state) = _setup();
      expect(
        AgentDecisions.next(engine, state, bombInterrupts: false),
        isA<TurnRequest>(),
      );
      state.deck = DeckState(
        TichuTurn(TurnType.empty, const []),
        CardFace.none,
      );
      expect(AgentDecisions.next(engine, state), isA<TurnRequest>());
    });

    test(
      'an interrupting bomb wins the trick and passes the turn on',
      () async {
        final (:engine, :state) = _setup();
        final request =
            AgentDecisions.next(engine, state)! as BombInterruptRequest;
        engine.applyAction(
          state,
          PlayTurnAction(
            playerId: testOpponentLeftId,
            cards: request.bombs.first.cards,
          ),
        );
        expect(state.lastPlayedBy, testOpponentLeftId);
        expect(state.deck.turn.type, TurnType.bomb);
        expect(state.players[state.currentPlayerIndex].seat, 2);
      },
    );

    test('bots do not bomb out of turn by default', () async {
      final s = _setup(winner: testHumanId);
      final request =
          AgentDecisions.next(s.engine, s.state)! as BombInterruptRequest;
      expect(
        await AgentDecisions.resolve(
          request,
          SmartAiAgent(testOpponentLeftId),
          s.engine.buildSnapshot(s.state),
          s.state,
        ),
        isA<DeclineBombAction>(),
      );
    });

    test('the heuristic bombs only against a dangerous opponent', () async {
      // The right player (left's partner) is winning: no bomb.
      var s = _setup();
      var agent = SmartAiAgent(
        testOpponentLeftId,
        options: HeuristicOptions.parse('interrupt_bomb'),
      );
      var request =
          AgentDecisions.next(s.engine, s.state)! as BombInterruptRequest;
      expect(
        await AgentDecisions.resolve(
          request,
          agent,
          s.engine.buildSnapshot(s.state),
          s.state,
        ),
        isA<DeclineBombAction>(),
      );

      // The human (an opponent, two cards left) is winning: bomb.
      s = _setup(winner: testHumanId);
      agent = SmartAiAgent(
        testOpponentLeftId,
        options: HeuristicOptions.parse('interrupt_bomb'),
      );
      request = AgentDecisions.next(s.engine, s.state)! as BombInterruptRequest;
      final action = await AgentDecisions.resolve(
        request,
        agent,
        s.engine.buildSnapshot(s.state),
        s.state,
      );
      expect(action, isA<PlayTurnAction>());
      expect((action! as PlayTurnAction).cards, hasLength(4));
    });
  });
}
