import 'package:tichu/game/game_backend.dart';

class TableRelationships {
  final GameSnapshot snapshot;
  final String playerId;
  final int mySeat;

  TableRelationships(this.snapshot, this.playerId)
    : mySeat = snapshot.players.firstWhere((final p) => p.id == playerId).seat;

  String? get partnerId {
    for (final player in snapshot.players) {
      if (player.id == playerId) {
        continue;
      }
      if (isPartner(player.id)) {
        return player.id;
      }
    }
    return null;
  }

  bool isPartner(final String candidateId) {
    if (candidateId == playerId) {
      return false;
    }
    final candidate = _playerOrNull(candidateId);
    if (candidate == null) {
      return false;
    }
    return candidate.seat % 2 == mySeat % 2;
  }

  bool isOpponent(final String candidateId) {
    if (candidateId == playerId) {
      return false;
    }
    final candidate = _playerOrNull(candidateId);
    if (candidate == null) {
      return false;
    }
    return candidate.seat % 2 != mySeat % 2;
  }

  Iterable<GamePlayer> get opponents =>
      snapshot.players.where((final player) => isOpponent(player.id));

  GamePlayer? playerOrNull(final String playerId) => _playerOrNull(playerId);

  int seatOf(final String playerId) =>
      snapshot.players.firstWhere((final p) => p.id == playerId).seat;

  int leftSeat() => (mySeat + 1) % 4;

  int rightSeat() => (mySeat + 3) % 4;

  GamePlayer playerBySeat(final int seat) =>
      snapshot.players.firstWhere((final p) => p.seat == seat);

  GamePlayer? _playerOrNull(final String playerId) {
    for (final player in snapshot.players) {
      if (player.id == playerId) {
        return player;
      }
    }
    return null;
  }
}
