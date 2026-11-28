import 'package:tichu/agents/endgame_search.dart';

/// The shipped bots: the assets and settings the app plays with
/// (`AppBots`). Plain Dart, so tools can build the same bots.
abstract final class ShippedBots {
  /// Trained play policy (rl/models/README.md): v10, schema v9 inputs.
  /// With [schupfAsset] and the belief search it beats the previous bot
  /// (v8 + schupf v4 + search <= 8) 63.7 %. Calls stay heuristic.
  static const playPolicyAsset = 'assets/bots/tichu_q_v10.safetensors';

  /// Learned schupf v5 (rl/schupf_cf_train.py) on the extended candidate
  /// set.
  static const schupfAsset = 'assets/bots/tichu_schupf_v5.safetensors';
  static const schupfExtended = true;

  /// Card-location model (rl/belief_train.py): the endgame search re-deals
  /// its worlds with it instead of uniformly.
  static const beliefAsset = 'assets/bots/tichu_belief_v1.safetensors';

  /// Decision-time endgame search and one-on-one solver for the app bots
  /// (rl/README.md, "Search at decision time"). Flip to switch it off.
  ///
  /// Sequential halving with the net's prior (rl/THEORY.md): the same 56
  /// rollouts as the former 8 worlds x 7 actions, spent on the moves still
  /// in contention, a challenger only when it beats the net's move by a
  /// standard error. Beats the former search (same nets) 56.0 % ± 1.1,
  /// +86 per match (600 deals x 2). ~95 ms per searched decision on one
  /// native core; the app spreads each halving round over its workers.
  static const useEndgameSearch = true;
  static const endgameSearch = EndgameSearch(
    maxCards: 12,
    solveOneOnOne: true,
    beliefWorlds: true,
    halvingBudget: 56,
    priorWeight: 1,
    minZ: 1,
  );
}
