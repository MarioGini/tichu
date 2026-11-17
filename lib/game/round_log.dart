import 'package:meta/meta.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// One play or pass of the current round, with the trick it answered.
///
/// This is public information (every player saw it happen). The bots read
/// hands from it: who played which cards, and what they declined to beat.
@immutable
class RoundLogEntry {
  final String playerId;

  /// Cards played; empty for a pass.
  final List<Card> cards;

  /// Top combination of the trick before this action (`empty` / `none` /
  /// `dog` = the player was leading).
  final TurnType trickType;
  final double trickValue;

  /// Player winning the trick before this action ('' when leading).
  final String trickWinner;

  const RoundLogEntry({
    required this.playerId,
    required this.cards,
    required this.trickType,
    required this.trickValue,
    required this.trickWinner,
  });

  bool get isPass => cards.isEmpty;
}
