import 'package:meta/meta.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/services/transport/dto/card_dto.dart';
import 'package:tichu/services/transport/dto/dto_helpers.dart';
import 'package:tichu/services/transport/dto/score_dto.dart';

export 'package:tichu/services/transport/dto/card_dto.dart';

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

  factory PlayerSnapshotDto.fromDomain(PlayerSnapshot snapshot) =>
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
    Map<String, dynamic> json,
  ) => PlayerSnapshotDto(
    gameId: json['gameId'] as String,
    players: decodeMapList(json['players'])
        .map(GamePlayerDto.fromJson)
        .toList(),
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
    pendingOpponentCards: decodeMapList(json['pendingOpponentCards'])
        .map(CardDto.fromJson)
        .toList(),
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
    schupfReceipts: decodeMapList(json['schupfReceipts'])
        .map(SchupfReceiptDto.fromJson)
        .toList(),
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
