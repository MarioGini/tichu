import 'package:tichu/agents/endgame_search.dart';
import 'package:tichu/game/player_agent.dart';

/// The web has no isolates: the search rolls out on the UI isolate.
RolloutWorkers? createSearchWorkers(
  PlayerAgent Function(String playerId, int seat) agentFor,
) => null;
