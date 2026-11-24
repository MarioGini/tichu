import 'package:tichu/game/agent_decisions.dart';
import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_exceptions.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';

/// The engine every simulation runs on: searches, solvers, rollouts and
/// training labels play out forks (`GameEngineState.copy`) of a game here,
/// never on the engine of the game itself, which may record or publish
/// moves (`RecordingGameEngine`, the match runtimes).
///
/// A plain [GameEngineImpl]: its moves are pure functions of the state, and
/// forks are mid-round, so its dealing Random is never used.
final GameEngine simulationEngine = GameEngineImpl();

/// Play [fork] to the end of the round on [simulationEngine] with
/// [agents]; returns team one's round points minus team two's, or null when
/// the playout got stuck.
Future<int?> playOutRound(
  final GameEngineState fork,
  final Map<String, PlayerAgent> agents,
) async {
  for (var steps = 0; steps < 5000; steps++) {
    final score = fork.scoreTracker.state;
    if (score.roundComplete) return score.teamOneRound - score.teamTwoRound;
    final request = AgentDecisions.next(simulationEngine, fork);
    if (request == null) return null;
    final snap = simulationEngine.buildSnapshot(fork);
    GameAction? action;
    try {
      action = await AgentDecisions.resolve(
        request,
        agents[request.playerId]!,
        snap,
        fork,
      );
    } on NoLegalActionException {
      return null;
    }
    if (action == null) continue;
    simulationEngine.applyAction(fork, action);
  }
  return null;
}
