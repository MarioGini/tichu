import 'package:meta/meta.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/services/transport/dto/dto_helpers.dart';

@immutable
class GamePlayerDto {
  final String id;
  final String name;
  final int seat;
  final String type;

  const GamePlayerDto({
    required this.id,
    required this.name,
    required this.seat,
    required this.type,
  });

  factory GamePlayerDto.fromDomain(GamePlayer player) => GamePlayerDto(
    id: player.id,
    name: player.name,
    seat: player.seat,
    type: player.type.name,
  );

  factory GamePlayerDto.fromJson(Map<String, dynamic> json) => GamePlayerDto(
    id: json['id'] as String,
    name: json['name'] as String,
    seat: (json['seat'] as num).toInt(),
    type: json['type'] as String,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'seat': seat,
    'type': type,
  };

  GamePlayer toDomain() => GamePlayer(
    id: id,
    name: name,
    seat: seat,
    type: enumByName(PlayerType.values, type),
  );
}

@immutable
class SchupfReceiptDto {
  final CardDto card;
  final String fromPlayerId;
  final String direction;

  const SchupfReceiptDto({
    required this.card,
    required this.fromPlayerId,
    required this.direction,
  });

  factory SchupfReceiptDto.fromDomain(SchupfReceipt receipt) =>
      SchupfReceiptDto(
        card: CardDto.fromDomain(receipt.card),
        fromPlayerId: receipt.fromPlayerId,
        direction: receipt.direction.name,
      );

  factory SchupfReceiptDto.fromJson(Map<String, dynamic> json) =>
      SchupfReceiptDto(
        card: CardDto.fromJson(Map<String, dynamic>.from(json['card'] as Map)),
        fromPlayerId: json['fromPlayerId'] as String,
        direction: json['direction'] as String,
      );

  Map<String, dynamic> toJson() => {
    'card': card.toJson(),
    'fromPlayerId': fromPlayerId,
    'direction': direction,
  };

  SchupfReceipt toDomain() => SchupfReceipt(
    card: card.toDomain(),
    fromPlayerId: fromPlayerId,
    direction: enumByName(SchupfDirection.values, direction),
  );
}

@immutable
class CardDto {
  final String face;
  final String color;
  final double value;

  const CardDto({required this.face, required this.color, required this.value});

  factory CardDto.fromDomain(Card card) =>
      CardDto(face: card.face.name, color: card.color.name, value: card.value);

  factory CardDto.fromJson(Map<String, dynamic> json) => CardDto(
    face: json['face'] as String,
    color: json['color'] as String,
    value: (json['value'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'face': face,
    'color': color,
    'value': value,
  };

  Card toDomain() {
    final resolvedFace = enumByName(CardFace.values, face);
    final resolvedColor = enumByName(CardColor.values, color);
    if (resolvedFace == CardFace.phoenix) {
      return Card.phoenix(value);
    }
    return Card(resolvedFace, resolvedColor);
  }
}

@immutable
class TichuTurnDto {
  final String type;
  final List<CardDto> cards;

  const TichuTurnDto({required this.type, required this.cards});

  factory TichuTurnDto.fromDomain(TichuTurn turn) => TichuTurnDto(
    type: turn.type.name,
    cards: [for (final card in turn.cards) CardDto.fromDomain(card)],
  );

  factory TichuTurnDto.fromJson(Map<String, dynamic> json) => TichuTurnDto(
    type: json['type'] as String,
    cards: decodeMapList(json['cards']).map(CardDto.fromJson).toList(),
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'cards': [for (final card in cards) card.toJson()],
  };

  TichuTurn toDomain() => TichuTurn(enumByName(TurnType.values, type), [
    for (final card in cards) card.toDomain(),
  ]);
}

@immutable
class DeckStateDto {
  final TichuTurnDto turn;
  final String wish;
  final String currentWinner;
  final List<CardDto> cardStack;

  const DeckStateDto({
    required this.turn,
    required this.wish,
    required this.currentWinner,
    required this.cardStack,
  });

  factory DeckStateDto.fromDomain(DeckState state) => DeckStateDto(
    turn: TichuTurnDto.fromDomain(state.turn),
    wish: state.wish.name,
    currentWinner: state.currentWinner,
    cardStack: [for (final card in state.cardStack) CardDto.fromDomain(card)],
  );

  factory DeckStateDto.fromJson(Map<String, dynamic> json) => DeckStateDto(
    turn: TichuTurnDto.fromJson(Map<String, dynamic>.from(json['turn'] as Map)),
    wish: json['wish'] as String,
    currentWinner: json['currentWinner'] as String? ?? '',
    cardStack: decodeMapList(json['cardStack']).map(CardDto.fromJson).toList(),
  );

  Map<String, dynamic> toJson() => {
    'turn': turn.toJson(),
    'wish': wish,
    'currentWinner': currentWinner,
    'cardStack': [for (final card in cardStack) card.toJson()],
  };

  DeckState toDomain() {
    final deck = DeckState(turn.toDomain(), enumByName(CardFace.values, wish));
    deck.currentWinner = currentWinner;
    deck.cardStack = [for (final card in cardStack) card.toDomain()];
    return deck;
  }
}
