import 'package:tichu/game/game_types.dart';

/// Seat offsets around the table, seen from the player at the bottom.
abstract final class TableSeat {
  static const int left = -1;
  static const int partner = 2;
  static const int right = 1;
}

/// The player sitting [seatOffset] seats from [selfSeat] (see [TableSeat]):
/// the table is rotated so that the player at [selfSeat] is at the bottom.
GamePlayer? playerAtRelativeSeat(
  List<GamePlayer> players,
  int? selfSeat,
  int seatOffset,
) {
  if (players.isEmpty || selfSeat == null) return null;
  final playerCount = players.length;
  final targetSeat = (selfSeat + seatOffset + playerCount) % playerCount;
  for (final player in players) {
    if (player.seat == targetSeat) return player;
  }
  return null;
}
