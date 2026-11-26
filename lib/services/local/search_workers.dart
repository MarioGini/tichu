import 'package:tichu/agents/endgame_search.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/services/local/search_workers_web.dart'
    if (dart.library.io) 'package:tichu/services/local/search_workers_io.dart'
    as impl;

/// Workers for the app's endgame search: long-lived isolates on phones and
/// desktop (one per core, at most 4), none on the web. [agentFor]
/// is sent to the isolates: it must capture only the bot config.
RolloutWorkers? createSearchWorkers(
  PlayerAgent Function(String playerId, int seat) agentFor,
) => impl.createSearchWorkers(agentFor);
