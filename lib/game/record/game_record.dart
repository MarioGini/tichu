import 'dart:math';

import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/record/round_log.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// Version of the JSON layout written by [GameRecord.toJson]: 3 stores one
/// [RoundLog] string per round (initial cards and move order); 1 stored
/// the full event list.
const int gameRecordFormatVersion = 3;

/// Random (version 4) UUID, used as game id and record id.
String generateUuidV4([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')]
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Short, readable card label: rank plus colour letter (g/b/k/r for
/// green/blue/black/red), or the name of a special card.
///
/// Examples: `Ag`, `10r`, `2k`, `Dragon`, `Phoenix`, `Dog`, `MahJong`.
String cardLabel(Card card) {
  switch (card.face) {
    case CardFace.dragon:
      return 'Dragon';
    case CardFace.phoenix:
      return 'Phoenix';
    case CardFace.dog:
      return 'Dog';
    case CardFace.mahJong:
      return 'MahJong';
    case CardFace.none:
      return '?';
    case CardFace.two ||
        CardFace.three ||
        CardFace.four ||
        CardFace.five ||
        CardFace.six ||
        CardFace.seven ||
        CardFace.eight ||
        CardFace.nine ||
        CardFace.ten ||
        CardFace.jack ||
        CardFace.queen ||
        CardFace.king ||
        CardFace.ace:
      return '${faceLabel(card.face)}${_colorLetter(card.color)}';
  }
}

/// Rank label of a face (`2`..`10`, `J`, `Q`, `K`, `A`) or the special name.
String faceLabel(CardFace face) => switch (face) {
  CardFace.two => '2',
  CardFace.three => '3',
  CardFace.four => '4',
  CardFace.five => '5',
  CardFace.six => '6',
  CardFace.seven => '7',
  CardFace.eight => '8',
  CardFace.nine => '9',
  CardFace.ten => '10',
  CardFace.jack => 'J',
  CardFace.queen => 'Q',
  CardFace.king => 'K',
  CardFace.ace => 'A',
  CardFace.mahJong => 'MahJong',
  CardFace.dragon => 'Dragon',
  CardFace.phoenix => 'Phoenix',
  CardFace.dog => 'Dog',
  CardFace.none => '-',
};

String _colorLetter(CardColor color) => switch (color) {
  CardColor.green => 'g',
  CardColor.blue => 'b',
  CardColor.black => 'k',
  CardColor.red => 'r',
  CardColor.special => '',
};

/// Labels of [cards], highest first (display order).
List<String> cardLabels(Iterable<Card> cards) {
  final sorted = [...cards]..sort(compareCardsForDisplay);
  return [for (final c in sorted) cardLabel(c)];
}

/// One entry of a game record. [seq] numbers events across the whole game,
/// so a move can be referred to as e.g. "#57".
class GameRecordEvent {
  GameRecordEvent({
    required this.seq,
    required this.round,
    required this.kind,
    required this.text,
    this.playerId,
    this.data = const <String, Object?>{},
    DateTime? at,
  }) : at = at ?? DateTime.now().toUtc();

  final int seq;
  final int round;

  /// One of: `deal`, `grandTichu`, `tichu`, `schupf`, `hands`, `play`,
  /// `pass`, `trick`, `out`, `dragon`, `roundEnd`, `gameEnd`.
  final String kind;

  /// Human-readable one-line description (shown in observe mode).
  final String text;
  final String? playerId;
  final Map<String, Object?> data;
  final DateTime at;

  Map<String, Object?> toJson() => {
    'seq': seq,
    'round': round,
    'kind': kind,
    if (playerId != null) 'player': playerId,
    'text': text,
    'at': at.toIso8601String(),
    ...data,
  };
}

/// The full history of one match: players, every decision with the hand it
/// was made from, trick results and round scores.
///
/// Stored as JSON (see `GameRecordStore`) under its [id], which is the
/// match / game id.
class GameRecord {
  GameRecord({
    required this.id,
    required this.players,
    required this.targetScore,
    this.botDescription,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc(),
       updatedAt = createdAt ?? DateTime.now().toUtc();

  final String id;
  final List<GamePlayer> players;
  final int targetScore;
  final String? botDescription;
  final DateTime createdAt;
  DateTime updatedAt;

  /// Detailed timeline, kept in memory for the app (observe mode, tests);
  /// not stored.
  final List<GameRecordEvent> events = [];

  /// Compact per-round logs: the stored form of the game.
  final List<RoundLog> roundLogs = [];

  /// Actions recorded so far; numbers moves as the viewer tool does.
  int get actionCount => roundLogs.fold(0, (n, r) => n + r.actionCount);

  int teamOneTotal = 0;
  int teamTwoTotal = 0;
  int roundsPlayed = 0;
  bool complete = false;
  int? winningTeam;

  /// `observe` when every seat is a bot, otherwise `play`.
  String get mode =>
      players.every((p) => p.type == PlayerType.automated) ? 'observe' : 'play';

  String nameOf(String? playerId) {
    if (playerId == null) return '?';
    for (final p in players) {
      if (p.id == playerId) return p.name;
    }
    return playerId;
  }

  GamePlayer? playerAtSeat(int seat) {
    for (final p in players) {
      if (p.seat == seat) return p;
    }
    return null;
  }

  GameRecordEvent add({
    required int round,
    required String kind,
    required String text,
    String? playerId,
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    final event = GameRecordEvent(
      seq: events.length + 1,
      round: round,
      kind: kind,
      text: text,
      playerId: playerId,
      data: data,
    );
    events.add(event);
    updatedAt = event.at;
    return event;
  }

  Map<String, Object?> summaryJson() => {
    'id': id,
    'mode': mode,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'rounds': roundsPlayed,
    'teamOneTotal': teamOneTotal,
    'teamTwoTotal': teamTwoTotal,
    'complete': complete,
    'winningTeam': ?winningTeam,
  };

  Map<String, Object?> toJson() => {
    'format': gameRecordFormatVersion,
    ...summaryJson(),
    'targetScore': targetScore,
    'bots': ?botDescription,
    'notation': 'lib/game/record/round_log.dart',
    'teams': {
      'teamOne': [
        for (final p in players)
          if (p.seat.isEven) p.id,
      ],
      'teamTwo': [
        for (final p in players)
          if (p.seat.isOdd) p.id,
      ],
    },
    'players': [
      for (final p in players)
        {'id': p.id, 'name': p.name, 'seat': p.seat, 'type': p.type.name},
    ],
    'log': [for (final r in roundLogs) r.encode()],
  };
}
