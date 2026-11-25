// Replays the game records of a headless bc-jsonl file (`--record-games`)
// and checks that they are complete: every round is replayed in the
// engine from its recorded deal and actions, the state features of every
// play row (found by its `round` / `step`) are recomputed and compared with
// the logged ones, and the round results must match.
//
//   dart compile exe lib/headless/replay_game_records.dart -o build/bin/replay_records
//   build/bin/replay_records rollout.jsonl
//
// The same replay is how any future feature can be computed for old data.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:tichu/agents/nn/feature_encoder.dart';
import 'package:tichu/game/agent_decisions.dart';
import 'package:tichu/game/card_identifiers.dart';
import 'package:tichu/game/game_actions.dart';
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

Future<void> main(List<String> args) async {
  final byEpisode = <int, List<Map<String, dynamic>>>{};
  for (final line in File(args.single).readAsLinesSync()) {
    if (!line.contains('"game_record"') && !line.contains('"step"')) continue;
    final row = jsonDecode(line) as Map<String, dynamic>;
    (byEpisode[row['episode'] as int] ??= []).add(row);
  }
  var rounds = 0;
  var roundsOk = 0;
  var rows = 0;
  var rowsOk = 0;
  for (final MapEntry(key: episode, value: list) in byEpisode.entries) {
    final records = [
      for (final r in list)
        if (r['game_record'] == true) r,
    ];
    final plays = <String, Map<String, dynamic>>{
      for (final r in list)
        if (r['step'] != null) '${r['round']}:${r['step']}': r,
    };
    final engine = GameEngineImpl(random: Random(0));
    final state = engine.createGame(
      gameId: 'replay_$episode',
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
      final actions = rec['actions'] as List<dynamic>;
      for (var k = 0; k < actions.length; k++) {
        AgentDecisions.next(engine, state);
        final row = plays['${rec['round']}:$k'];
        if (row != null) {
          rows++;
          final action = _decode(actions[k] as List<dynamic>);
          final got = encodeStateFeatures(
            snapshot: engine.buildSnapshot(state),
            playerId: action.playerId,
          );
          final want = (row['state_features'] as List<dynamic>).cast<num>();
          var same = got.length == want.length;
          for (var j = 0; same && j < got.length; j++) {
            if ((got[j] - want[j]).abs() > 1e-6) same = false;
          }
          if (same) rowsOk++;
        }
        engine.applyAction(state, _decode(actions[k] as List<dynamic>));
      }
      rounds++;
      final s = state.scoreTracker.state;
      final result = rec['result'] as List<dynamic>;
      if (s.roundComplete &&
          s.teamOneRound == result[0] &&
          s.teamTwoRound == result[1]) {
        roundsOk++;
      }
    }
  }
  stdout.writeln(
    'rounds replayed: $roundsOk / $rounds with the recorded result; '
    'play rows: $rowsOk / $rows with identical state features',
  );
  if (roundsOk != rounds || rowsOk != rows) exitCode = 1;
}
