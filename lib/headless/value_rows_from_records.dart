// Value-net training rows from recorded games (`--record-games`, the
// `*.games.jsonl.xz` files in Supabase Storage): replays every round in the
// engine from its deal and actions and, for a sample of play-phase turns,
// writes the player's state features, who holds every card, and how the
// round ended (rl/value_data.py --records reads them).
//
//   dart compile exe lib/headless/value_rows_from_records.dart \
//       -o build/bin/value_rows
//   xzcat run.games.jsonl.xz | build/bin/value_rows --rate=0.2 --seed=1
//
// One JSON line per row:
//   {"s": [state features], "h": [56 x holder: -1 none, 0 left, 1 partner,
//    2 right], "y": [our round points, theirs], "f": first out (0 self,
//    1 left, 2 partner, 3 right), "d": double victory (0 us, 1 them, 2 no)}
//
// No net runs, so this is far cheaper than self-play. Rounds whose replay
// does not reach the recorded result are skipped, and so is the rest of a
// match after a recorded move the current rules reject (records from
// before a rule fix); both are counted on stderr.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:tichu/agents/card_knowledge.dart';
import 'package:tichu/agents/nn/feature_encoder.dart';
import 'package:tichu/game/agent_decisions.dart';
import 'package:tichu/game/card_identifiers.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_exceptions.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';
import 'package:tichu/game/turn/tichu_data.dart';

const _players = [
  GamePlayer(id: 'auto_1', name: 'P1', seat: 0, type: PlayerType.automated),
  GamePlayer(id: 'auto_2', name: 'P2', seat: 1, type: PlayerType.automated),
  GamePlayer(id: 'auto_3', name: 'P3', seat: 2, type: PlayerType.automated),
  GamePlayer(id: 'auto_4', name: 'P4', seat: 3, type: PlayerType.automated),
];

final Map<int, Card> _bySlot = {
  for (final c in cardIdentifiers.values) cardSlot(c): c,
};

GameAction _decode(List<dynamic> a) {
  final id = _players[a[0] as int].id;
  return switch (a[1] as String) {
    'g' => GrandTichuDecisionAction(playerId: id, call: a[2] == 1),
    't' => CallTichuAction(playerId: id),
    'G' => CallGrandTichuAction(playerId: id),
    's' => SchupfAction(
      playerId: id,
      toLeft: _bySlot[a[2]]!,
      toPartner: _bySlot[a[3]]!,
      toRight: _bySlot[a[4]]!,
    ),
    'a' => AcknowledgeSchupfAction(playerId: id),
    'p' => PlayTurnAction(
      playerId: id,
      cards: [for (final s in a[2] as List<dynamic>) _bySlot[s as int]!],
      inputWish: CardFace.values[a[3] as int],
    ),
    'x' => PassAction(playerId: id),
    'd' => GiveDragonAction(
      playerId: id,
      targetPlayerId: _players[a[2] as int].id,
    ),
    'c' => ConfirmOpponentTurnAction(playerId: id),
    final other => throw StateError('unknown action code $other'),
  };
}

int _seatOf(String id) => _players.firstWhere((p) => p.id == id).seat;

Future<void> main(List<String> args) async {
  var rate = 0.2;
  var seed = 1;
  for (final arg in args) {
    if (arg.startsWith('--rate=')) {
      rate = double.parse(arg.substring('--rate='.length));
    } else if (arg.startsWith('--seed=')) {
      seed = int.parse(arg.substring('--seed='.length));
    } else {
      stderr.writeln('Unknown argument: $arg');
      exitCode = 64;
      return;
    }
  }
  final random = Random(seed);
  final byEpisode = <int, List<Map<String, dynamic>>>{};
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (!line.contains('"game_record"')) continue;
    final row = jsonDecode(line) as Map<String, dynamic>;
    (byEpisode[row['episode'] as int] ??= []).add(row);
  }
  var rounds = 0;
  var skipped = 0;
  var written = 0;
  for (final MapEntry(key: episode, value: records) in byEpisode.entries) {
    records.sort((a, b) => (a['round'] as int).compareTo(b['round'] as int));
    final engine = GameEngineImpl(random: Random(0));
    final state = engine.createGame(
      gameId: 'value_$episode',
      players: _players,
    );
    engine.startGame(state);
    for (var i = 0; i < records.length; i++) {
      final rec = records[i];
      if (i > 0) engine.startNewRound(state);
      final deal = rec['deal'] as List<dynamic>;
      for (var seat = 0; seat < 4; seat++) {
        final cards = [
          for (final s in deal[seat] as List<dynamic>) _bySlot[s as int]!,
        ];
        state.hands[_players[seat].id] = cards.sublist(0, 8);
        state.reservedHands[_players[seat].id] = cards.sublist(8);
      }
      // (state features, holders, seat) of the sampled turns.
      final pending = <(List<double>, List<int>, int)>[];
      var illegal = false;
      for (final a in rec['actions'] as List<dynamic>) {
        final request = AgentDecisions.next(engine, state);
        if (request is TurnRequest && random.nextDouble() < rate) {
          final seat = _seatOf(request.playerId);
          final holders = List<int>.filled(CardKnowledge.slotCount, -1);
          for (var k = 0; k < 3; k++) {
            final id = _players[(seat + 1 + k) % 4].id;
            for (final card in state.hands[id] ?? const <Card>[]) {
              holders[cardSlot(card)] = k;
            }
          }
          pending.add((
            encodeStateFeatures(
              snapshot: engine.buildSnapshot(state),
              playerId: request.playerId,
            ),
            holders,
            seat,
          ));
        }
        try {
          engine.applyAction(state, _decode(a as List<dynamic>));
        } on IllegalActionException {
          // Recorded before a rule fix (e.g. #45): the rest of the match
          // no longer replays.
          illegal = true;
          break;
        }
      }
      rounds++;
      if (illegal) {
        skipped++;
        break;
      }
      final score = state.scoreTracker.state;
      final result = rec['result'] as List<dynamic>;
      if (!score.roundComplete ||
          score.teamOneRound != result[0] ||
          score.teamTwoRound != result[1]) {
        skipped++;
        continue;
      }
      final order = [for (final id in score.finishOrder) _seatOf(id)];
      for (final (s, h, seat) in pending) {
        final team = seat % 2;
        final us = team == 0 ? score.teamOneRound : score.teamTwoRound;
        final them = team == 0 ? score.teamTwoRound : score.teamOneRound;
        final doubleWin = order.length >= 2 && order[0] % 2 == order[1] % 2
            ? (order[0] % 2 == team ? 0 : 1)
            : 2;
        stdout.writeln(
          jsonEncode({
            's': s,
            'h': h,
            'y': [us, them],
            'f': order.isEmpty ? 0 : (order[0] - seat) % 4,
            'd': doubleWin,
          }),
        );
        written++;
      }
    }
  }
  stderr.writeln(
    'rounds: $rounds replayed, $skipped skipped (illegal under the '
    'current rules or result differs); '
    '$written rows',
  );
}
