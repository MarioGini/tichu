// Reviews every one-on-one endgame decision of a bot against exact values.
//
//   dart compile exe lib/headless/review_one_on_one.dart -o build/bin/review_1v1
//   build/bin/review_1v1 --nn-policy=assets/bots/tichu_q_v10.safetensors \
//       --schupf-net=assets/bots/tichu_schupf_v5.safetensors --schupf-extended \
//       --episodes=50 --seed=1 [--search] [--max-cards=10] --output=1v1.jsonl
//
// Self-play of the configured bot (the app's bot with --search). At every
// play decision with two players of different teams left (the opponent's
// hand is then known) and at most --max-cards cards in the two hands, it
// writes one row: the position, every legal action with its exact minimax
// value for the decider's team (OneOnOneSolver.values), and the action the
// bot chose. Dragon gifts in one-on-one are reviewed the same way.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:tichu/agents/bot_config.dart';
import 'package:tichu/agents/endgame_search.dart';
import 'package:tichu/agents/endgame_solver.dart';
import 'package:tichu/agents/legal_play_guard.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/agent_decisions.dart';
import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';
import 'package:tichu/game/turn/move_generator.dart';
import 'package:tichu/game/turn/tichu_data.dart';

Future<void> main(List<String> args) async {
  String? opt(String name) {
    for (final a in args) {
      if (a.startsWith('--$name=')) return a.substring(name.length + 3);
    }
    return null;
  }

  final episodes = int.parse(opt('episodes') ?? '20');
  final seed = int.parse(opt('seed') ?? '1');
  final maxCards = int.parse(opt('max-cards') ?? '10');
  final search = args.contains('--search');
  final out = File(opt('output') ?? '1v1.jsonl').openWrite();
  Future<LoadedNet?> load(String? p) async =>
      p == null ? null : LoadedNet.fromBytes(await File(p).readAsBytes());
  final plain = BotConfig(
    play: await load(opt('nn-policy')),
    schupf: await load(opt('schupf-net')),
    simdInference: true,
  );
  final config = search
      ? plain.withEndgameSearch(const EndgameSearch(maxCards: 8))
      : plain;
  PlayerAgent plainAgent(String id, int _) => plain.build(id);
  final searcher = EndgameSearcher(rolloutAgent: plainAgent);
  final engine = GameEngineImpl(random: Random(seed));
  const players = [
    GamePlayer(id: 'p1', name: 'P1', seat: 0, type: PlayerType.automated),
    GamePlayer(id: 'p2', name: 'P2', seat: 1, type: PlayerType.automated),
    GamePlayer(id: 'p3', name: 'P3', seat: 2, type: PlayerType.automated),
    GamePlayer(id: 'p4', name: 'P4', seat: 3, type: PlayerType.automated),
  ];
  var rows = 0;
  var giveUps = 0;
  for (var ep = 0; ep < episodes; ep++) {
    final state = engine.createGame(gameId: 'r$seed-$ep', players: players);
    engine.startGame(state);
    final agents = {for (final p in players) p.id: config.build(p.id)};
    for (var steps = 0; steps < 200000; steps++) {
      final score = state.scoreTracker.state;
      if (score.gameComplete) break;
      if (score.roundComplete) {
        engine.startNewRound(state);
        continue;
      }
      final request = AgentDecisions.next(engine, state);
      if (request == null) break;
      final agent = agents[request.playerId]!;
      final snap = engine.buildSnapshot(state);
      var action = await AgentDecisions.resolve(request, agent, snap, state);
      if (action == null) continue;
      if (request is TurnRequest && search) {
        action = await searcher.refine(
          state: state,
          agent: agent,
          chosen: action,
        );
      }
      final pid = request.playerId;
      final reviewed =
          (request is TurnRequest || request is DragonGiveRequest) &&
          _oneOnOne(state, maxCards);
      if (reviewed &&
          (action is PlayTurnAction ||
              action is PassAction ||
              action is GiveDragonAction)) {
        final snapNow = engine.buildSnapshot(state);
        final options = _options(engine, state, request, agent);
        if (options.length >= 2) {
          final solver = OneOnOneSolver(
            agentFor: plainAgent,
            nodeBudget: 200000,
          );
          final values = await solver.values(state, pid, options);
          if (values.any((v) => v == null)) {
            giveUps++;
          } else {
            final chosen = options.indexWhere((o) => _same(o, action!));
            out.writeln(
              jsonEncode(
                _row(state, pid, request, options, values, chosen)
                  ..['trick_points'] = snapNow.trickPoints,
              ),
            );
            rows++;
            if (rows % 20 == 0) await out.flush();
          }
        }
      }
      engine.applyAction(state, action);
    }
  }
  await out.flush();
  await out.close();
  stderr.writeln('$rows decisions reviewed, $giveUps too large');
}

bool _oneOnOne(GameEngineState s, int maxCards) {
  final active = [
    for (final p in s.players)
      if (s.hands[p.id]?.isNotEmpty ?? false) p,
  ];
  if (active.length != 2 || active[0].seat % 2 == active[1].seat % 2) {
    return false;
  }
  return active.fold<int>(0, (n, p) => n + s.hands[p.id]!.length) <= maxCards;
}

List<GameAction> _options(
  GameEngine engine,
  GameEngineState state,
  DecisionRequest request,
  PlayerAgent agent,
) {
  if (request is DragonGiveRequest) {
    return [
      for (final id in request.opponentIds)
        GiveDragonAction(playerId: request.playerId, targetPlayerId: id),
    ];
  }
  final pid = request.playerId;
  final snap = engine.buildSnapshot(state);
  final hand = List<Card>.from(state.hands[pid] ?? const <Card>[]);
  final turns = LegalPlayGuard.filterMoveGeneratorTurns(
    deck: snap.deck,
    hand: hand,
    moveGeneratorTurns: generateLegalTurns(snap.deck, hand),
  );
  return [
    for (final t in turns)
      if (agent is SmartAiAgent)
        agent.playActionFor(snap, t)
      else
        PlayTurnAction(playerId: pid, cards: t.cards),
    if (LegalPlayGuard.canPass(deck: snap.deck, hand: hand))
      PassAction(playerId: pid),
  ];
}

String _key(List<Card> cards) =>
    (cards.map((c) => '${c.face.index}.${c.color.index}').toList()..sort())
        .join(',');

bool _same(GameAction a, GameAction b) {
  if (a is PassAction && b is PassAction) return true;
  if (a is PlayTurnAction && b is PlayTurnAction) {
    return _key(a.cards) == _key(b.cards);
  }
  if (a is GiveDragonAction && b is GiveDragonAction) {
    return a.targetPlayerId == b.targetPlayerId;
  }
  return false;
}

String _tok(Card c) => switch (c.face) {
  CardFace.dog => 'Dog',
  CardFace.mahJong => '1',
  CardFace.phoenix => 'Ph',
  CardFace.dragon => 'Dr',
  CardFace.ten => 'T',
  CardFace.jack => 'J',
  CardFace.queen => 'Q',
  CardFace.king => 'K',
  CardFace.ace => 'A',
  _ => '${c.value.toInt()}',
};

int _order(Card c) => switch (c.face) {
  CardFace.dog => 0,
  CardFace.mahJong => 1,
  CardFace.phoenix => 15,
  CardFace.dragon => 16,
  _ => c.value.toInt(),
};

String _cards(List<Card> cards) {
  final s = [...cards]..sort((a, b) => _order(a) - _order(b));
  return s.map(_tok).join(' ');
}

Map<String, Object?> _row(
  GameEngineState s,
  String pid,
  DecisionRequest request,
  List<GameAction> options,
  List<int?> values,
  int chosen,
) {
  final me = s.players.firstWhere((p) => p.id == pid);
  final opp = s.players.firstWhere(
    (p) => p.seat % 2 != me.seat % 2 && (s.hands[p.id]?.isNotEmpty ?? false),
    orElse: () => me,
  );
  final score = s.scoreTracker.state;
  String desc(GameAction a) => switch (a) {
    PassAction() => 'pass',
    PlayTurnAction(:final cards) => _cards(cards),
    GiveDragonAction(:final targetPlayerId) =>
      'dragon->${targetPlayerId == opp.id ? 'opponent in play' : 'opponent out'}',
    _ => '?',
  };
  final first = score.finishOrder.isEmpty ? null : score.finishOrder.first;
  return {
    'kind': request is DragonGiveRequest ? 'dragon' : 'play',
    'me': _cards(s.hands[pid] ?? const []),
    'opp': _cards(s.hands[opp.id] ?? const []),
    'trick': _cards(s.deck.turn.cards),
    'trick_type': s.deck.turn.type.name,
    'leading':
        s.deck.turn.type == TurnType.empty || s.deck.turn.type == TurnType.none,
    'winner_is_me': s.deck.currentWinner == pid,
    'first_out_mine': first == null
        ? null
        : s.players.firstWhere((p) => p.id == first).seat % 2 == me.seat % 2,
    'wish': s.deck.wish.name,
    'actions': [for (final a in options) desc(a)],
    'values': values,
    'chosen': chosen,
  };
}
