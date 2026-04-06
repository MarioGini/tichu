import 'package:meta/meta.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/services/transport/dto/dto_helpers.dart';
import 'package:tichu/services/transport/dto/snapshot_dto.dart';

@immutable
class GameActionDto {
  final String kind;
  final String playerId;
  final List<CardDto> cards;
  final String? inputWish;
  final String? targetPlayerId;
  final bool? call;
  final CardDto? toLeft;
  final CardDto? toPartner;
  final CardDto? toRight;

  const GameActionDto({
    required this.kind,
    required this.playerId,
    this.cards = const <CardDto>[],
    this.inputWish,
    this.targetPlayerId,
    this.call,
    this.toLeft,
    this.toPartner,
    this.toRight,
  });

  factory GameActionDto.fromDomain(final GameAction action) {
    return switch (action) {
      PlayTurnAction() => GameActionDto(
        kind: 'playTurn',
        playerId: action.playerId,
        cards: [for (final card in action.cards) CardDto.fromDomain(card)],
        inputWish: action.inputWish.name,
      ),
      PassAction() => GameActionDto(kind: 'pass', playerId: action.playerId),
      GiveDragonAction() => GameActionDto(
        kind: 'giveDragon',
        playerId: action.playerId,
        targetPlayerId: action.targetPlayerId,
      ),
      ConfirmOpponentTurnAction() => GameActionDto(
        kind: 'confirmOpponentTurn',
        playerId: action.playerId,
      ),
      CallTichuAction() => GameActionDto(
        kind: 'callTichu',
        playerId: action.playerId,
      ),
      CallGrandTichuAction() => GameActionDto(
        kind: 'callGrandTichu',
        playerId: action.playerId,
      ),
      GrandTichuDecisionAction() => GameActionDto(
        kind: 'grandTichuDecision',
        playerId: action.playerId,
        call: action.call,
      ),
      SchupfAction() => GameActionDto(
        kind: 'schupf',
        playerId: action.playerId,
        toLeft: CardDto.fromDomain(action.toLeft),
        toPartner: CardDto.fromDomain(action.toPartner),
        toRight: CardDto.fromDomain(action.toRight),
      ),
      AcknowledgeSchupfAction() => GameActionDto(
        kind: 'acknowledgeSchupf',
        playerId: action.playerId,
      ),
      _ => throw UnsupportedError(
        'Unsupported action type: ${action.runtimeType}',
      ),
    };
  }

  factory GameActionDto.fromJson(final Map<String, dynamic> json) =>
      GameActionDto(
        kind: json['kind'] as String,
        playerId: json['playerId'] as String,
        cards: decodeMapList(json['cards']).map(CardDto.fromJson).toList(),
        inputWish: json['inputWish'] as String?,
        targetPlayerId: json['targetPlayerId'] as String?,
        call: json['call'] as bool?,
        toLeft: decodeNullableMap(json['toLeft'], CardDto.fromJson),
        toPartner: decodeNullableMap(json['toPartner'], CardDto.fromJson),
        toRight: decodeNullableMap(json['toRight'], CardDto.fromJson),
      );

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'playerId': playerId,
    'cards': [for (final card in cards) card.toJson()],
    'inputWish': inputWish,
    'targetPlayerId': targetPlayerId,
    'call': call,
    'toLeft': toLeft?.toJson(),
    'toPartner': toPartner?.toJson(),
    'toRight': toRight?.toJson(),
  };

  GameAction toDomain() {
    return switch (kind) {
      'playTurn' => PlayTurnAction(
        playerId: playerId,
        cards: [for (final card in cards) card.toDomain()],
        inputWish: enumByName(CardFace.values, inputWish ?? CardFace.none.name),
      ),
      'pass' => PassAction(playerId: playerId),
      'giveDragon' => GiveDragonAction(
        playerId: playerId,
        targetPlayerId: targetPlayerId!,
      ),
      'confirmOpponentTurn' => ConfirmOpponentTurnAction(playerId: playerId),
      'callTichu' => CallTichuAction(playerId: playerId),
      'callGrandTichu' => CallGrandTichuAction(playerId: playerId),
      'grandTichuDecision' => GrandTichuDecisionAction(
        playerId: playerId,
        call: call ?? false,
      ),
      'schupf' => SchupfAction(
        playerId: playerId,
        toLeft: toLeft!.toDomain(),
        toPartner: toPartner!.toDomain(),
        toRight: toRight!.toDomain(),
      ),
      'acknowledgeSchupf' => AcknowledgeSchupfAction(playerId: playerId),
      _ => throw UnsupportedError('Unknown action kind: $kind'),
    };
  }
}
