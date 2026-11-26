import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/round_log.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// Plain JSON (maps, lists, numbers, strings) of a whole
/// [GameEngineState], so a state can be sent to a web worker (the web's
/// endgame search, `search_workers_web.dart`): dart2js workers share no
/// Dart objects. [decodeEngineState] rebuilds an equal state: cards are
/// compared by value everywhere, so new card objects are fine.
Map<String, Object?> encodeEngineState(GameEngineState s) {
  Map<String, Object?> hands(Map<String, List<Card>> m) => {
    for (final e in m.entries) e.key: _cards(e.value),
  };
  return {
    'gameId': s.gameId,
    'players': [
      for (final p in s.players) [p.id, p.name, p.seat, p.type.index],
    ],
    'hands': hands(s.hands),
    'reserved': hands(s.reservedHands),
    'score': s.scoreTracker.toJson(_card),
    'deck': [
      _turn(s.deck.turn),
      s.deck.wish.index,
      s.deck.currentWinner,
      _cards(s.deck.cardStack),
    ],
    'current': s.currentPlayerIndex,
    'passes': s.consecutivePasses,
    'lastPlayedBy': s.lastPlayedBy,
    'lastPlayedTurn': s.lastPlayedTurn == null
        ? null
        : _turn(s.lastPlayedTurn!),
    'lastDragonGiveBy': s.lastDragonGiveBy,
    'lastDragonGiveTo': s.lastDragonGiveTo,
    'pendingDragonGiveBy': s.pendingDragonGiveBy,
    'pendingDragonGiveTargets': s.pendingDragonGiveTargets,
    'pendingDragonTrickCards': _cards(s.pendingDragonTrickCards),
    'currentTrickCards': _cards(s.currentTrickCards),
    'finished': s.finishedPlayers.toList(),
    'playedThisRound': s.playersWhoPlayedCardsThisRound.toList(),
    'roundLog': [
      for (final e in s.roundLog)
        [
          e.playerId,
          _cards(e.cards),
          e.trickType.index,
          e.trickValue,
          e.trickWinner,
        ],
    ],
    'phase': s.phase.index,
    'grandTichu': s.grandTichuDecisions,
    'schupf': _schupfs(s.schupfSelections),
    'completedSchupf': _schupfs(s.completedSchupfSelections),
    'receipts': {
      for (final e in s.schupfReceipts.entries)
        e.key: [
          for (final r in e.value)
            [_card(r.card), r.fromPlayerId, r.direction.index],
        ],
    },
    'pendingAdditions': hands(s.schupfPendingAdditions),
  };
}

/// The state [encodeEngineState] wrote.
GameEngineState decodeEngineState(Map<String, Object?> json) {
  Map<String, List<Card>> hands(Object? m) => {
    for (final e in (m! as Map).entries) e.key as String: _decodeCards(e.value),
  };
  List<String> strings(Object? list) => [
    for (final s in list! as List) s! as String,
  ];
  final deck = json['deck']! as List;
  final s =
      GameEngineState(
          gameId: json['gameId']! as String,
          players: [
            for (final p in json['players']! as List)
              GamePlayer(
                id: (p as List)[0]! as String,
                name: p[1]! as String,
                seat: p[2]! as int,
                type: PlayerType.values[p[3]! as int],
              ),
          ],
          hands: hands(json['hands']),
          deck:
              DeckState(_decodeTurn(deck[0]), CardFace.values[deck[1]! as int])
                ..currentWinner = deck[2]! as String
                ..cardStack = _decodeCards(deck[3]),
          currentPlayerIndex: json['current']! as int,
          scoreTracker: LocalScoreTracker.fromJson(
            Map<String, Object?>.from(json['score']! as Map),
            _decodeCard,
          ),
          reservedHands: hands(json['reserved']),
          phase: GamePhase.values[json['phase']! as int],
        )
        ..consecutivePasses = json['passes']! as int
        ..lastPlayedBy = json['lastPlayedBy'] as String?
        ..lastPlayedTurn = json['lastPlayedTurn'] == null
            ? null
            : _decodeTurn(json['lastPlayedTurn'])
        ..lastDragonGiveBy = json['lastDragonGiveBy'] as String?
        ..lastDragonGiveTo = json['lastDragonGiveTo'] as String?
        ..pendingDragonGiveBy = json['pendingDragonGiveBy'] as String?;
  s.pendingDragonGiveTargets.addAll(strings(json['pendingDragonGiveTargets']));
  s.pendingDragonTrickCards.addAll(
    _decodeCards(json['pendingDragonTrickCards']),
  );
  s.currentTrickCards.addAll(_decodeCards(json['currentTrickCards']));
  s.finishedPlayers.addAll(strings(json['finished']));
  s.playersWhoPlayedCardsThisRound.addAll(strings(json['playedThisRound']));
  for (final e in json['roundLog']! as List) {
    final entry = e as List;
    s.roundLog.add(
      RoundLogEntry(
        playerId: entry[0]! as String,
        cards: _decodeCards(entry[1]),
        trickType: TurnType.values[entry[2]! as int],
        trickValue: (entry[3]! as num).toDouble(),
        trickWinner: entry[4]! as String,
      ),
    );
  }
  for (final e in (json['grandTichu']! as Map).entries) {
    s.grandTichuDecisions[e.key as String] = e.value! as bool;
  }
  s.schupfSelections.addAll(_decodeSchupfs(json['schupf']));
  s.completedSchupfSelections.addAll(_decodeSchupfs(json['completedSchupf']));
  for (final e in (json['receipts']! as Map).entries) {
    s.schupfReceipts[e.key as String] = [
      for (final r in e.value! as List)
        SchupfReceipt(
          card: _decodeCard((r as List)[0]),
          fromPlayerId: r[1]! as String,
          direction: SchupfDirection.values[r[2]! as int],
        ),
    ];
  }
  s.schupfPendingAdditions.addAll(hands(json['pendingAdditions']));
  return s;
}

/// A play or pass (the actions the endgame search rolls out).
Object? encodeSearchAction(GameAction action) => switch (action) {
  PlayTurnAction(:final playerId, :final cards, :final inputWish) => [
    playerId,
    _cards(cards),
    inputWish.index,
  ],
  PassAction(:final playerId) => [playerId],
  _ => throw ArgumentError.value(action, 'action', 'not a play or pass'),
};

GameAction decodeSearchAction(Object? json) {
  final a = json! as List;
  final playerId = a[0]! as String;
  if (a.length == 1) return PassAction(playerId: playerId);
  return PlayTurnAction(
    playerId: playerId,
    cards: _decodeCards(a[1]),
    inputWish: CardFace.values[a[2]! as int],
  );
}

Object? _card(Card c) => [c.face.index, c.color.index, c.value];

Card _decodeCard(Object? json) {
  final c = json! as List;
  final face = CardFace.values[c[0]! as int];
  final value = (c[2]! as num).toDouble();
  return face == CardFace.phoenix
      ? Card.phoenix(value)
      : Card(face, CardColor.values[c[1]! as int]);
}

List<Object?> _cards(List<Card> cards) => [for (final c in cards) _card(c)];

List<Card> _decodeCards(Object? json) => [
  for (final c in json! as List) _decodeCard(c),
];

Object? _turn(TichuTurn t) => [t.type.index, _cards(t.cards)];

TichuTurn _decodeTurn(Object? json) {
  final t = json! as List;
  return TichuTurn(TurnType.values[t[0]! as int], _decodeCards(t[1]));
}

Map<String, Object?> _schupfs(Map<String, SchupfAction> m) => {
  for (final e in m.entries)
    e.key: [
      _card(e.value.toLeft),
      _card(e.value.toPartner),
      _card(e.value.toRight),
    ],
};

Map<String, SchupfAction> _decodeSchupfs(Object? json) => {
  for (final e in (json! as Map).entries)
    e.key as String: SchupfAction(
      playerId: e.key as String,
      toLeft: _decodeCard((e.value! as List)[0]),
      toPartner: _decodeCard((e.value! as List)[1]),
      toRight: _decodeCard((e.value! as List)[2]),
    ),
};
