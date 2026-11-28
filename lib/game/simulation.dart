import 'package:tichu/game/agent_decisions.dart';
import 'package:tichu/game/engine.dart';
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
  GameEngineState fork,
  Map<String, PlayerAgent> agents,
) async {
  final points = await playOutRoundPoints(fork, agents);
  if (points == null) return null;
  return (points.$1 - points.$2).round();
}

/// Estimated round points (team one, team two) of [state], in which
/// [playerId] is to play: a value net's guess where a playout stops early.
typedef LeafValue = (double, double) Function(
  GameEngineState state,
  String playerId,
);

/// Play [fork] on [simulationEngine] with [agents] and return the round
/// points of team one and team two, or null when the playout got stuck.
///
/// With [leaf], the playout stops at the first turn of the play phase after
/// [leafAfter] actions and returns [leaf]'s estimate there instead (a
/// truncated rollout: the search pays for [leafAfter] moves, not for the
/// whole round). Without it, the round is played to the end.
Future<(double, double)?> playOutRoundPoints(
  GameEngineState fork,
  Map<String, PlayerAgent> agents, {
  int leafAfter = 0,
  LeafValue? leaf,
}) async {
  for (var steps = 0; steps < 5000; steps++) {
    final score = fork.scoreTracker.state;
    if (score.roundComplete) {
      return (score.teamOneRound.toDouble(), score.teamTwoRound.toDouble());
    }
    final request = AgentDecisions.next(simulationEngine, fork);
    if (request == null) return null;
    if (leaf != null && steps >= leafAfter && request is TurnRequest) {
      return leaf(fork, request.playerId);
    }
    final snap = simulationEngine.buildSnapshot(fork);
    final action = await AgentDecisions.resolve(
      request,
      agents[request.playerId]!,
      snap,
      fork,
    );
    if (action == null) continue;
    simulationEngine.applyAction(fork, action);
  }
  return null;
}
