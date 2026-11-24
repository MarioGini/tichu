import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/agent_decisions.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';
import 'package:tichu/game/turn/tichu_data.dart';

const _players = [
  GamePlayer(id: 'p1', name: 'P1', seat: 0, type: PlayerType.automated),
  GamePlayer(id: 'p2', name: 'P2', seat: 1, type: PlayerType.automated),
  GamePlayer(id: 'p3', name: 'P3', seat: 2, type: PlayerType.automated),
  GamePlayer(id: 'p4', name: 'P4', seat: 3, type: PlayerType.automated),
];

/// A player who goes out with a single Phoenix (two or more others still
/// holding cards): the others may still beat it or pass; when all pass the
/// trick (Phoenix -25) goes to the player who went out and the next active
/// player after them leads.
void main() {
  test('going out with the Phoenix: the others answer, then the next player '
      'leads and the out player takes the trick', () async {
    final engine = GameEngineImpl(random: Random(4));
    final state = engine.createGame(
      gameId: 'phoenix_out',
      players: _players,
      targetScore: 1000000,
    );
    engine.startGame(state);
    final agents = {for (final p in _players) p.id: SmartAiAgent(p.id)};
    var checked = 0;
    var allPassed = 0;
    String? outPlayer;
    int? pointsBefore;
    var trickPoints = 0;
    var othersBefore = <String, int>{};
    var anyPlay = false;
    final answered = <String>{};
    var passes = 0;
    for (var steps = 0; steps < 400000 && (checked < 6 || allPassed < 1); steps++) {
      if (state.scoreTracker.state.roundComplete) {
        outPlayer = null;
        engine.startNewRound(state);
        continue;
      }
      final request = AgentDecisions.next(engine, state);
      if (request == null) fail('no pending decision');
      final action = await AgentDecisions.resolve(
        request,
        agents[request.playerId]!,
        engine.buildSnapshot(state),
        state,
      );
      if (action == null) continue;
      final before = state.hands[action.playerId]?.length ?? 0;
      if (outPlayer != null) {
        trickPoints = engine.buildSnapshot(state).trickPoints;
      }
      final watching = outPlayer;
      if (watching != null && action is! GiveDragonAction) {
        answered.add(action.playerId);
        if (action is PassAction) passes++;
        if (action is PlayTurnAction) anyPlay = true;
      }
      engine.applyAction(state, action);
      if (watching != null) {
        final trickOver = state.deck.turn.type == TurnType.empty;
        if (trickOver || state.scoreTracker.state.roundComplete) {
          final active = [
            for (final p in state.players)
              if (!state.finishedPlayers.contains(p.id)) p.id,
          ];
          if (!anyPlay &&
              passes == answered.length &&
              state.pendingDragonGiveBy == null &&
              !state.scoreTracker.state.roundComplete) {
            // Everyone passed: the out player took the trick, the next
            // active player after them leads.
            allPassed++;
            final points = state.scoreTracker.state.playerRoundPoints;
            expect(
              points[watching],
              pointsBefore! + trickPoints,
              reason: 'the trick goes to the player who went out',
            );
            for (final e in othersBefore.entries) {
              expect(points[e.key] ?? 0, e.value, reason: '${e.key} unchanged');
            }
            final outIndex = state.players.indexWhere(
              (final p) => p.id == watching,
            );
            var next = (outIndex + 1) % 4;
            while (state.finishedPlayers.contains(state.players[next].id)) {
              next = (next + 1) % 4;
            }
            expect(state.currentPlayerIndex, next);
            expect(answered, containsAll(active));
          }
          checked++;
          outPlayer = null;
        }
        continue;
      }
      if (action is PlayTurnAction &&
          before == 1 &&
          action.cards.single.face == CardFace.phoenix &&
          state.finishedPlayers.length <= 2 &&
          !state.scoreTracker.state.roundComplete) {
        outPlayer = action.playerId;
        final points = state.scoreTracker.state.playerRoundPoints;
        pointsBefore = points[action.playerId] ?? 0;
        othersBefore = {
          for (final p in state.players)
            if (p.id != action.playerId) p.id: points[p.id] ?? 0,
        };
        answered.clear();
        passes = 0;
        anyPlay = false;
      }
    }
    expect(checked, greaterThanOrEqualTo(6));
    expect(allPassed, greaterThan(0));
  });
}
