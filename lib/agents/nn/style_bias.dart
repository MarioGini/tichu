import 'package:tichu/game/turn/tichu_data.dart';

/// A fixed tilt of the play net's choices, for style experiments
/// (`headless --style=` / `--opponent-style=`): a bonus for passing and a
/// penalty for spending control cards (Dragon, Phoenix, Aces, bombs) while
/// the hand is still big. Both in round points; zero = the net unchanged.
class StyleBias {
  /// Added to the pass action's value (points).
  final double passBonus;

  /// Subtracted per control card a play spends (points), while the hand has
  /// at least [spendMinHand] cards.
  final double spendPenalty;
  final int spendMinHand;

  const StyleBias({
    this.passBonus = 0,
    this.spendPenalty = 0,
    this.spendMinHand = 8,
  });

  static const none = StyleBias();

  bool get isNone => passBonus == 0 && spendPenalty == 0;

  /// Control cards a play spends: Dragon, Phoenix, Aces; a bomb counts 1.
  static int controls(final TichuTurn play) {
    if (play.type == TurnType.bomb) return 1;
    var n = 0;
    for (final c in play.cards) {
      if (c.face == CardFace.dragon ||
          c.face == CardFace.phoenix ||
          c.face == CardFace.ace) {
        n++;
      }
    }
    return n;
  }

  /// Parses `pass:20,spend:15,min-hand:8` (any subset; `none` = no bias).
  factory StyleBias.parse(final String spec) {
    var pass = 0.0;
    var spend = 0.0;
    var minHand = 8;
    for (final raw in spec.split(',')) {
      final token = raw.trim();
      if (token.isEmpty || token == 'none') continue;
      final i = token.indexOf(':');
      final value = i > 0 ? double.tryParse(token.substring(i + 1)) : null;
      if (value == null) throw ArgumentError('Invalid style token: $token');
      switch (token.substring(0, i)) {
        case 'pass':
          pass = value;
        case 'spend':
          spend = value;
        case 'min-hand':
          minHand = value.round();
        default:
          throw ArgumentError('Unknown style key: $token');
      }
    }
    return StyleBias(
      passBonus: pass,
      spendPenalty: spend,
      spendMinHand: minHand,
    );
  }

  @override
  String toString() => isNone
      ? 'none'
      : 'pass:$passBonus,spend:$spendPenalty,min-hand:$spendMinHand';
}
