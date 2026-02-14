import 'package:tichu/game/game_backend.dart';

class TableRelationships {
  final GameSnapshot snapshot;
  final String playerId;
  final int mySeat;

  TableRelationships(this.snapshot, this.playerId)
    : mySeat = snapshot.players.firstWhere((p) => p.id == playerId).seat;

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

  bool isPartner(String candidateId) {
    if (candidateId == playerId) {
      return false;
    }
    final candidate = _playerOrNull(candidateId);
    if (candidate == null) {
      return false;
    }
    return candidate.seat % 2 == mySeat % 2;
  }

  bool isOpponent(String candidateId) {
    if (candidateId == playerId) {
      return false;
    }
    final candidate = _playerOrNull(candidateId);
    if (candidate == null) {
      return false;
    }
    return candidate.seat % 2 != mySeat % 2;
  }

  Iterable<GamePlayer> get opponents {
    return snapshot.players.where((player) => isOpponent(player.id));
  }

  GamePlayer? playerOrNull(String playerId) => _playerOrNull(playerId);

  int seatOf(String playerId) {
    return snapshot.players.firstWhere((p) => p.id == playerId).seat;
  }

  int leftSeat() => (mySeat + 1) % 4;

  int rightSeat() => (mySeat + 3) % 4;

  GamePlayer playerBySeat(int seat) {
    return snapshot.players.firstWhere((p) => p.seat == seat);
  }

  GamePlayer? _playerOrNull(String playerId) {
    for (final player in snapshot.players) {
      if (player.id == playerId) {
        return player;
      }
    }
    return null;
  }
}
