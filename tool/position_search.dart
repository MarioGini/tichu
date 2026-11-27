// Analyses one decision of a stored game with the endgame search: replays
// the game to just before an action and rolls out every move of the player
// to act in re-dealt worlds, as the search does.
//
//   dart run tool/position_search.dart <game-id | round-id | file.json>
//       --step N [--worlds 64] [--uniform]
//
// N is the action number tool/game_record.dart prints (`#208`). Records are
// found as for tool/game_record.dart. The bots are the shipped ones
// (lib/agents/shipped_bots.dart); the worlds are re-dealt with the belief
// model unless --uniform.
//
// Prints the position, the policy's move, for each move the mean round
// result for the mover's team over the worlds and in how many worlds it is
// better / worse than the policy's move, its result with the real hands,
// and what the shipped decision rule and the expected-value rule pick.
import 'dart:io';
import 'dart:math';

import 'package:tichu/agents/bot_config.dart';
import 'package:tichu/agents/endgame_search.dart';
import 'package:tichu/agents/nn/belief_model.dart';
import 'package:tichu/agents/shipped_bots.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/record/game_record_replay.dart';
import 'package:tichu/game/record/round_log.dart';
import 'package:tichu/game/scoring/score_state.dart';
import 'package:tichu/game/simulation.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'src/record_source.dart';

const _usage =
    'Usage: dart run tool/position_search.dart <game-id | round-id | '
    'file.json> --step N [--worlds 64] [--uniform]';

Future<void> main(List<String> args) async {
  int? intArg(String flag) {
    final i = args.indexOf(flag);
    return i >= 0 && i + 1 < args.length ? int.parse(args[i + 1]) : null;
  }

  final step = intArg('--step');
  if (args.isEmpty ||
      args.contains('-h') ||
      args.contains('--help') ||
      step == null) {
    stdout.writeln(_usage);
    if (step == null &&
        args.isNotEmpty &&
        !args.contains('--help') &&
        !args.contains('-h')) {
      exitCode = 64;
    }
    return;
  }
  final worlds = intArg('--worlds') ?? 64;
  final uniform = args.contains('--uniform');

  final loaded = await loadRecord(args.first);
  if (loaded == null) {
    exitCode = 1;
    return;
  }
  final record = loaded.record;
  final rounds = switch (record['log']) {
    final List<Object?> log => log.cast<String>(),
    _ => null,
  };
  if (rounds == null) {
    stderr.writeln('Only format-3 records (one log per round) replay');
    exitCode = 1;
    return;
  }
  final players = [
    for (final p in (record['players']! as List).cast<Map<String, Object?>>())
      GamePlayer(
        id: p['id']! as String,
        name: p['name']! as String,
        seat: p['seat']! as int,
        type: PlayerType.automated,
      ),
  ];
  // The action #step must be an on-turn play or pass.
  final names = [
    for (var seat = 0; seat < 4; seat++)
      players.firstWhere((p) => p.seat == seat).name,
  ];
  final allSteps = [for (final r in rounds) ...replayRoundLog(r, names)];
  if (step < 1 || step > allSteps.length) {
    stderr.writeln('No action #$step: the record has ${allSteps.length}');
    exitCode = 1;
    return;
  }
  final target = allSteps[step - 1];
  if (target.kind != RoundLogKind.play && target.kind != RoundLogKind.pass) {
    stderr.writeln('#$step is not a play or pass: ${target.text}');
    exitCode = 1;
    return;
  }
  final state = replayGameRecord(
    engine: simulationEngine,
    players: players,
    rounds: rounds,
    gameId: record['id']! as String,
    targetScore: (record['targetScore'] as int?) ?? 1000,
    before: step,
  );
  if (state.phase != GamePhase.play ||
      state.pendingDragonGiveBy != null ||
      state.players[state.currentPlayerIndex].seat != target.seat) {
    stderr.writeln('#$step is not an on-turn decision: ${target.text}');
    exitCode = 1;
    return;
  }

  final me = state.players[state.currentPlayerIndex];
  String name(String id) => players.firstWhere((p) => p.id == id).name;
  final score = state.scoreTracker.state;
  stdout.writeln(
    '#$step: ${me.name} to act; score '
    '${score.teamOneTotal}:${score.teamTwoTotal}',
  );
  for (final p in state.players) {
    final call = score.tichuCalls[p.id] ?? TichuCall.none;
    stdout.writeln(
      '  ${p.name.padRight(8)} ${_cards(state.hands[p.id]!)}'
      '${call == TichuCall.none ? '' : '  (${call.name})'}',
    );
  }
  final table = state.deck.turn.cards;
  stdout.writeln(
    table.isEmpty
        ? '  on lead'
        : '  on the table: ${_cards(table)} by ${name(state.lastPlayedBy!)}',
  );

  final bots = _shippedBots();
  PlayerAgent rollout(String id, int _) => bots.plain.build(id);
  final agent = bots.plain.build(me.id) as SmartAiAgent;
  final snapshot = simulationEngine.buildSnapshot(state);
  final policy = await agent.selectTurn(snapshot);
  final options = agent.searchableActions(snapshot);
  if (options == null) {
    stdout.writeln('Policy: ${_label(policy)} (forced or finishing move)');
    return;
  }
  final actions = <int, GameAction>{
    for (var i = 0; i < options.turns.length; i++)
      i: agent.playActionFor(snapshot, options.turns[i]),
    if (options.canPass) options.turns.length: PassAction(playerId: me.id),
  };
  final chosen = actions.entries
      .firstWhere((e) => _sameMove(e.value, policy))
      .key;
  final team = me.seat % 2;

  final random = Random(EndgameSearcher.searchSeed(state, me.id));
  final holders = uniform
      ? null
      : bots.belief.holderProbabilities(snapshot, me.id);
  final deals = [
    for (var w = 0; w < worlds; w++)
      dealUnseen(state, me.id, random, holders: holders),
  ];
  final values = await EndgameSearcher.rollOutWorlds(
    state,
    deals,
    actions,
    actions.length,
    team,
    rollout,
  );
  final realHands = <String, List<Card>>{
    for (final p in state.players)
      if (p.id != me.id) p.id: [...state.hands[p.id]!],
  };
  final real = (await EndgameSearcher.rollOutWorlds(
    state,
    [realHands],
    actions,
    actions.length,
    team,
    rollout,
  )).single;

  stdout.writeln(
    "\nPolicy: ${_label(policy)}. Round result for ${me.name}'s team, "
    '$worlds ${uniform ? 'uniform' : 'belief'} worlds:',
  );
  stdout.writeln(
    '  ${'move'.padRight(18)}${'mean'.padLeft(8)}  better/worse  real hands',
  );
  for (final MapEntry(key: i, value: action) in actions.entries) {
    final column = [for (final row in values) row[i]];
    final known = column.whereType<double>().toList();
    final mean = known.isEmpty
        ? double.nan
        : known.reduce((a, b) => a + b) / known.length;
    var better = 0;
    var worse = 0;
    for (final row in values) {
      final (a, c) = (row[i], row[chosen]);
      if (a == null || c == null) continue;
      if (a > c) better++;
      if (a < c) worse++;
    }
    final mark = i == chosen ? '*' : ' ';
    stdout.writeln(
      '$mark ${_label(action).padRight(18)}'
      '${mean.toStringAsFixed(1).padLeft(8)}  '
      '${'+$better -$worse'.padLeft(12)}  '
      '${real[i]?.toStringAsFixed(0) ?? '-'}',
    );
  }
  const shipped = ShippedBots.endgameSearch;
  for (final expectedValue in [false, true]) {
    final pick = pickEndgameAction(
      values,
      chosen,
      shipped.margin,
      minBetterWorlds: shipped.minBetterWorlds,
      expectedValue: expectedValue,
    );
    stdout.writeln(
      '${expectedValue ? 'Expected-value rule' : 'Shipped rule'} '
      'on these worlds: ${_label(actions[pick]!)}',
    );
  }

  // The search itself, with the shipped settings (its own worlds).
  for (final expectedValue in [false, true]) {
    final searching = bots.plain.withEndgameSearch(
      shipped.copyWith(expectedValue: expectedValue),
    );
    final searcher = EndgameSearcher(
      rolloutAgent: rollout,
      belief: bots.belief,
    );
    final searchAgent = searching.build(me.id);
    final move = await searchAgent.selectTurn(snapshot);
    final refined = await searcher.refine(
      state: state.copy(),
      agent: searchAgent,
      chosen: move,
    );
    final ran = searcher.searches + searcher.solves > 0;
    stdout.writeln(
      'Search as shipped${expectedValue ? ' + expectedValue' : ''}: '
      '${_label(refined)}'
      '${ran ? '' : ' (the search does not apply here)'}',
    );
  }
}

/// The shipped bots without the search, and the belief model.
({BotConfig plain, BeliefModel belief}) _shippedBots() {
  LoadedNet net(String asset) =>
      LoadedNet.fromBytes(File(asset).readAsBytesSync());
  return (
    plain: BotConfig(
      play: net(ShippedBots.playPolicyAsset),
      schupf: net(ShippedBots.schupfAsset),
      schupfExtended: ShippedBots.schupfExtended,
      simdInference: true,
    ),
    belief: BeliefModel(net(ShippedBots.beliefAsset).network),
  );
}

/// Card labels; a Phoenix in a combination with the rank it stands for.
String _cards(List<Card> cards) => cards
    .map(
      (c) => c.face == CardFace.phoenix && c.value >= 2
          ? 'Phoenix(${c.value.toStringAsFixed(0)})'
          : cardIndexLabel(cardIndex(c)),
    )
    .join(' ');

bool _sameMove(GameAction a, GameAction b) => switch ((a, b)) {
  (PassAction(), PassAction()) => true,
  (final PlayTurnAction x, final PlayTurnAction y) =>
    EndgameSearcher.slotKey(x.cards) == EndgameSearcher.slotKey(y.cards) &&
        _phoenixValue(x) == _phoenixValue(y),
  _ => false,
};

double? _phoenixValue(PlayTurnAction play) => [
  for (final c in play.cards)
    if (c.face == CardFace.phoenix) c.value,
].firstOrNull;

String _label(GameAction action) =>
    action is PlayTurnAction ? _cards(action.cards) : 'pass';
