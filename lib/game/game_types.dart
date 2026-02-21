import 'package:tichu/game/turn/tichu_data.dart';

enum PlayerType { human, automated }

enum GamePhase { grandTichu, schupf, play }

enum SchupfDirection { left, partner, right }

class SchupfReceipt {
  final Card card;
  final String fromPlayerId;
  final SchupfDirection direction;

  const SchupfReceipt({
    required this.card,
    required this.fromPlayerId,
    required this.direction,
  });
}

class GamePlayer {
  final String id;
  final String name;
  final int seat;
  final PlayerType type;

  const GamePlayer({
    required this.id,
    required this.name,
    required this.seat,
    required this.type,
  });
}
