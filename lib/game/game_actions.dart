import 'package:tichu/game/turn/tichu_data.dart';

abstract class GameAction {
  final String playerId;

  const GameAction({required this.playerId});
}

class PlayTurnAction extends GameAction {
  final List<Card> cards;
  final CardFace inputWish;

  const PlayTurnAction({
    required super.playerId,
    required this.cards,
    this.inputWish = CardFace.none,
  });
}

class PassAction extends GameAction {
  const PassAction({required super.playerId});
}

class GiveDragonAction extends GameAction {
  final String targetPlayerId;

  const GiveDragonAction({
    required super.playerId,
    required this.targetPlayerId,
  });
}

class ConfirmOpponentTurnAction extends GameAction {
  const ConfirmOpponentTurnAction({required super.playerId});
}

class CallTichuAction extends GameAction {
  const CallTichuAction({required super.playerId});
}

class CallGrandTichuAction extends GameAction {
  const CallGrandTichuAction({required super.playerId});
}

class GrandTichuDecisionAction extends GameAction {
  final bool call;

  const GrandTichuDecisionAction({required super.playerId, required this.call});
}

class SchupfAction extends GameAction {
  final Card toLeft;
  final Card toPartner;
  final Card toRight;

  const SchupfAction({
    required super.playerId,
    required this.toLeft,
    required this.toPartner,
    required this.toRight,
  });
}

class AcknowledgeSchupfAction extends GameAction {
  const AcknowledgeSchupfAction({required super.playerId});
}
