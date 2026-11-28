import 'package:tichu/agents/endgame_search.dart';
import 'package:tichu/agents/partner_convention.dart';

/// The shipped bots: the assets and settings the app plays with
/// (`AppBots`). Plain Dart, so tools can build the same bots.
abstract final class ShippedBots {
  /// Trained play policy (rl/README.md): v10, schema v9 inputs.
  /// With [schupfAsset] and the belief search it beats the previous bot
  /// (v8 + schupf v4 + search <= 8) 63.7 %. Calls stay heuristic.
  static const playPolicyAsset = 'assets/bots/tichu_q_v10.safetensors';

  /// Learned schupf v5 (rl/schupf_cf_train.py) on the extended candidate
  /// set.
  static const schupfAsset = 'assets/bots/tichu_schupf_v5.safetensors';
  static const schupfExtended = true;

  /// Partner-passing convention "2+ HC Odd" (tichuengine.com/about): the
  /// card to the partner tells how many high cards the passer kept, and
  /// the search reads it. See [PartnerConvention].
  static const PartnerConvention partnerConvention = PartnerConvention.twoHcOdd;

  /// Card-location model (rl/belief_train.py): the endgame search re-deals
  /// its worlds with it instead of uniformly.
  static const beliefAsset = 'assets/bots/tichu_belief_v1.safetensors';

  /// Decision-time endgame search and one-on-one solver for the app bots
  /// (rl/README.md, "Search at decision time"). Flip to switch it off.
  /// ~70 ms per searched decision natively (more on phones and the web).
  static const useEndgameSearch = true;
  static const endgameSearch = EndgameSearch(
    maxCards: 12,
    solveOneOnOne: true,
    beliefWorlds: true,
  );
}
