import 'package:meta/meta.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/services/transport/dto/dto_helpers.dart';
import 'package:tichu/services/transport/dto/score_dto.dart';

@immutable
class PlayerSnapshotDto {
  final String gameId;
  final List<GamePlayerDto> players;
  final List<CardDto> hand;
  final Map<String, int> opponentCardCounts;
  final DeckStateDto deck;
  final int trickPoints;
  final String activeWish;
  final String currentPlayerId;
  final int consecutivePasses;
  final String? lastPlayedBy;
  final TichuTurnDto? lastPlayedTurn;
  final String? lastDragonGiveBy;
  final String? lastDragonGiveTo;
  final String? pendingDragonGiveBy;
  final List<String> pendingDragonGiveTargets;
  final String? pendingOpponentPlayerId;
  final List<CardDto> pendingOpponentCards;
  final bool pendingOpponentPass;
  final ScoreStateDto scoreState;
  final bool opponentAwaitingConfirmation;
  final String phase;
  final bool canCallTichu;
  final bool hasBombInHand;
  final bool canBomb;
  final Map<String, bool> grandTichuDecisions;
  final List<String> schupfCompletedPlayers;
  final List<SchupfReceiptDto> schupfReceipts;

  const PlayerSnapshotDto({
    required this.gameId,
    required this.players,
    required this.hand,
    required this.opponentCardCounts,
    required this.deck,
    required this.trickPoints,
    required this.activeWish,
    required this.currentPlayerId,
    required this.consecutivePasses,
    required this.lastPlayedBy,
    required this.lastPlayedTurn,
    required this.lastDragonGiveBy,
    required this.lastDragonGiveTo,
    required this.pendingDragonGiveBy,
    required this.pendingDragonGiveTargets,
    required this.pendingOpponentPlayerId,
    required this.pendingOpponentCards,
    required this.pendingOpponentPass,
    required this.scoreState,
    required this.opponentAwaitingConfirmation,
    required this.phase,
    required this.canCallTichu,
    required this.hasBombInHand,
    required this.canBomb,
    required this.grandTichuDecisions,
    required this.schupfCompletedPlayers,
    required this.schupfReceipts,
  });

  factory PlayerSnapshotDto.fromDomain(final PlayerSnapshot snapshot) =>
      PlayerSnapshotDto(
        gameId: snapshot.gameId,
        players: [
          for (final player in snapshot.players)
            GamePlayerDto.fromDomain(player),
        ],
        hand: [for (final card in snapshot.hand) CardDto.fromDomain(card)],
        opponentCardCounts: snapshot.opponentCardCounts,
        deck: DeckStateDto.fromDomain(snapshot.deck),
        trickPoints: snapshot.trickPoints,
        activeWish: snapshot.activeWish.name,
        currentPlayerId: snapshot.currentPlayerId,
        consecutivePasses: snapshot.consecutivePasses,
        lastPlayedBy: snapshot.lastPlayedBy,
        lastPlayedTurn: snapshot.lastPlayedTurn == null
            ? null
            : TichuTurnDto.fromDomain(snapshot.lastPlayedTurn!),
        lastDragonGiveBy: snapshot.lastDragonGiveBy,
        lastDragonGiveTo: snapshot.lastDragonGiveTo,
        pendingDragonGiveBy: snapshot.pendingDragonGiveBy,
        pendingDragonGiveTargets: snapshot.pendingDragonGiveTargets,
        pendingOpponentPlayerId: snapshot.pendingOpponentPlayerId,
        pendingOpponentCards: [
          for (final card in snapshot.pendingOpponentCards)
            CardDto.fromDomain(card),
        ],
        pendingOpponentPass: snapshot.pendingOpponentPass,
        scoreState: ScoreStateDto.fromDomain(snapshot.scoreState),
        opponentAwaitingConfirmation: snapshot.opponentAwaitingConfirmation,
        phase: snapshot.phase.name,
        canCallTichu: snapshot.canCallTichu,
        hasBombInHand: snapshot.hasBombInHand,
        canBomb: snapshot.canBomb,
        grandTichuDecisions: snapshot.grandTichuDecisions,
        schupfCompletedPlayers: snapshot.schupfCompletedPlayers,
        schupfReceipts: [
          for (final receipt in snapshot.schupfReceipts)
            SchupfReceiptDto.fromDomain(receipt),
        ],
      );

  factory PlayerSnapshotDto.fromJson(
    final Map<String, dynamic> json,
  ) => PlayerSnapshotDto(
    gameId: json['gameId'] as String,
    players: decodeMapList(
      json['players'],
    ).map(GamePlayerDto.fromJson).toList(),
    hand: decodeMapList(json['hand']).map(CardDto.fromJson).toList(),
    opponentCardCounts: decodeIntMap(json['opponentCardCounts']),
    deck: DeckStateDto.fromJson(Map<String, dynamic>.from(json['deck'] as Map)),
    trickPoints: (json['trickPoints'] as num).toInt(),
    activeWish: json['activeWish'] as String,
    currentPlayerId: json['currentPlayerId'] as String,
    consecutivePasses: (json['consecutivePasses'] as num).toInt(),
    lastPlayedBy: json['lastPlayedBy'] as String?,
    lastPlayedTurn: decodeNullableMap(
      json['lastPlayedTurn'],
      TichuTurnDto.fromJson,
    ),
    lastDragonGiveBy: json['lastDragonGiveBy'] as String?,
    lastDragonGiveTo: json['lastDragonGiveTo'] as String?,
    pendingDragonGiveBy: json['pendingDragonGiveBy'] as String?,
    pendingDragonGiveTargets: decodeStringList(
      json['pendingDragonGiveTargets'],
    ),
    pendingOpponentPlayerId: json['pendingOpponentPlayerId'] as String?,
    pendingOpponentCards: decodeMapList(
      json['pendingOpponentCards'],
    ).map(CardDto.fromJson).toList(),
    pendingOpponentPass: json['pendingOpponentPass'] as bool? ?? false,
    scoreState: ScoreStateDto.fromJson(
      Map<String, dynamic>.from(json['scoreState'] as Map),
    ),
    opponentAwaitingConfirmation:
        json['opponentAwaitingConfirmation'] as bool? ?? false,
    phase: json['phase'] as String,
    canCallTichu: json['canCallTichu'] as bool? ?? false,
    hasBombInHand: json['hasBombInHand'] as bool? ?? false,
    canBomb: json['canBomb'] as bool? ?? false,
    grandTichuDecisions: decodeBoolMap(json['grandTichuDecisions']),
    schupfCompletedPlayers: decodeStringList(json['schupfCompletedPlayers']),
    schupfReceipts: decodeMapList(
      json['schupfReceipts'],
    ).map(SchupfReceiptDto.fromJson).toList(),
  );

  Map<String, dynamic> toJson() => {
    'gameId': gameId,
    'players': [for (final player in players) player.toJson()],
    'hand': [for (final card in hand) card.toJson()],
    'opponentCardCounts': opponentCardCounts,
    'deck': deck.toJson(),
    'trickPoints': trickPoints,
    'activeWish': activeWish,
    'currentPlayerId': currentPlayerId,
    'consecutivePasses': consecutivePasses,
    'lastPlayedBy': lastPlayedBy,
    'lastPlayedTurn': lastPlayedTurn?.toJson(),
    'lastDragonGiveBy': lastDragonGiveBy,
    'lastDragonGiveTo': lastDragonGiveTo,
    'pendingDragonGiveBy': pendingDragonGiveBy,
    'pendingDragonGiveTargets': pendingDragonGiveTargets,
    'pendingOpponentPlayerId': pendingOpponentPlayerId,
    'pendingOpponentCards': [
      for (final card in pendingOpponentCards) card.toJson(),
    ],
    'pendingOpponentPass': pendingOpponentPass,
    'scoreState': scoreState.toJson(),
    'opponentAwaitingConfirmation': opponentAwaitingConfirmation,
    'phase': phase,
    'canCallTichu': canCallTichu,
    'hasBombInHand': hasBombInHand,
    'canBomb': canBomb,
    'grandTichuDecisions': grandTichuDecisions,
    'schupfCompletedPlayers': schupfCompletedPlayers,
    'schupfReceipts': [for (final receipt in schupfReceipts) receipt.toJson()],
  };

  PlayerSnapshot toDomain() => PlayerSnapshot(
    gameId: gameId,
    players: [for (final player in players) player.toDomain()],
    hand: [for (final card in hand) card.toDomain()],
    opponentCardCounts: opponentCardCounts,
    deck: deck.toDomain(),
    trickPoints: trickPoints,
    activeWish: enumByName(CardFace.values, activeWish),
    currentPlayerId: currentPlayerId,
    consecutivePasses: consecutivePasses,
    lastPlayedBy: lastPlayedBy,
    lastPlayedTurn: lastPlayedTurn?.toDomain(),
    lastDragonGiveBy: lastDragonGiveBy,
    lastDragonGiveTo: lastDragonGiveTo,
    pendingDragonGiveBy: pendingDragonGiveBy,
    pendingDragonGiveTargets: pendingDragonGiveTargets,
    pendingOpponentPlayerId: pendingOpponentPlayerId,
    pendingOpponentCards: [
      for (final card in pendingOpponentCards) card.toDomain(),
    ],
    pendingOpponentPass: pendingOpponentPass,
    scoreState: scoreState.toDomain(),
    opponentAwaitingConfirmation: opponentAwaitingConfirmation,
    phase: enumByName(GamePhase.values, phase),
    canCallTichu: canCallTichu,
    hasBombInHand: hasBombInHand,
    canBomb: canBomb,
    grandTichuDecisions: grandTichuDecisions,
    schupfCompletedPlayers: schupfCompletedPlayers,
    schupfReceipts: [for (final receipt in schupfReceipts) receipt.toDomain()],
  );
}

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

  factory GamePlayerDto.fromDomain(final GamePlayer player) => GamePlayerDto(
    id: player.id,
    name: player.name,
    seat: player.seat,
    type: player.type.name,
  );

  factory GamePlayerDto.fromJson(final Map<String, dynamic> json) =>
      GamePlayerDto(
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

  factory SchupfReceiptDto.fromDomain(final SchupfReceipt receipt) =>
      SchupfReceiptDto(
        card: CardDto.fromDomain(receipt.card),
        fromPlayerId: receipt.fromPlayerId,
        direction: receipt.direction.name,
      );

  factory SchupfReceiptDto.fromJson(final Map<String, dynamic> json) =>
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

  factory CardDto.fromDomain(final Card card) =>
      CardDto(face: card.face.name, color: card.color.name, value: card.value);

  factory CardDto.fromJson(final Map<String, dynamic> json) => CardDto(
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

  factory TichuTurnDto.fromDomain(final TichuTurn turn) => TichuTurnDto(
    type: turn.type.name,
    cards: [for (final card in turn.cards) CardDto.fromDomain(card)],
  );

  factory TichuTurnDto.fromJson(final Map<String, dynamic> json) =>
      TichuTurnDto(
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

  factory DeckStateDto.fromDomain(final DeckState state) => DeckStateDto(
    turn: TichuTurnDto.fromDomain(state.turn),
    wish: state.wish.name,
    currentWinner: state.currentWinner,
    cardStack: [for (final card in state.cardStack) CardDto.fromDomain(card)],
  );

  factory DeckStateDto.fromJson(
    final Map<String, dynamic> json,
  ) => DeckStateDto(
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
