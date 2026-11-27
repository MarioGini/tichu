// Plays our bot in one seat at tichuengine.com against its bots.
//
//   dart run tool/tichuengine_client.dart --games=3 --strength=Grandmaster
//       [--jwt-file=path] [--out=arena/results/tichuengine.jsonl]
//       [shipped bot flags: --nn-policy=.. --schupf-net=.. --belief-net=..]
//
// Our bot takes seat 0, its partner and both opponents are the site's bots
// of the given strength: equal bots win 50 % of games.
//
// The server sends every seat's cards to every client. This client reads
// only what seat 0 may know: its own hand, its first eight cards, the card
// each opponent passed to it, and the public moves. The other hands are
// rebuilt in our engine as a guess that explains every public move (as
// the arena adapters do), and our bot decides from that state.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:tichu/agents/bot_config.dart';
import 'package:tichu/agents/endgame_search.dart';
import 'package:tichu/agents/nn/belief_model.dart';
import 'package:tichu/game/agent_decisions.dart';
import 'package:tichu/game/engine_state.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_exceptions.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';
import 'package:tichu/game/turn/find_turn.dart';
import 'package:tichu/game/turn/move_generator.dart';
import 'package:tichu/game/turn/tichu_data.dart';

const _me = 0;
const _base = 'https://api.tichuengine.com';

// ── Cards ────────────────────────────────────────────────────────────────

const List<CardFace> _faces = [
  CardFace.two,
  CardFace.three,
  CardFace.four,
  CardFace.five,
  CardFace.six,
  CardFace.seven,
  CardFace.eight,
  CardFace.nine,
  CardFace.ten,
  CardFace.jack,
  CardFace.queen,
  CardFace.king,
  CardFace.ace,
];
const List<CardColor> _colors = [
  CardColor.black,
  CardColor.blue,
  CardColor.green,
  CardColor.red,
];

Card cardOf(int id) => switch (id) {
  0 => Card(CardFace.phoenix, CardColor.special),
  1 => Card(CardFace.dragon, CardColor.special),
  2 => Card(CardFace.dog, CardColor.special),
  3 => Card(CardFace.mahJong, CardColor.special),
  _ => Card(_faces[(id - 4) % 13], _colors[(id - 4) ~/ 13]),
};

int idOf(Card c) => switch (c.face) {
  CardFace.phoenix => 0,
  CardFace.dragon => 1,
  CardFace.dog => 2,
  CardFace.mahJong => 3,
  _ => 4 + _colors.indexOf(c.color) * 13 + _faces.indexOf(c.face),
};

/// Cards as ids, the Phoenix by its face only.
List<int> idsOf(Iterable<Card> cards) =>
    [for (final c in cards) idOf(c)]..sort();

int _rankOf(CardFace f) => _faces.indexOf(f) + 2;

// Server combination types.
const _pass = 0;
const _dog = 9;
const _giveDragon = 10;
const _makeWish = 11;
const _bet = 12;

int typeOf(TichuTurn t) => switch (t.type) {
  TurnType.single => 1,
  TurnType.pair => 2,
  TurnType.triplet => 3,
  TurnType.pairStraight => 4,
  TurnType.fullHouse => 5,
  TurnType.straight => 6,
  TurnType.bomb => t.cards.length == 4 ? 7 : 8,
  TurnType.dog => _dog,
  _ => throw StateError('No server type for ${t.type}'),
};

/// The server's rank of [t]: a card's rank (Mah Jong 1, Dragon 15), a
/// single Phoenix the rank it beats, otherwise the combination's own.
int rankOf(TichuTurn t, TichuTurn? trick) {
  if (t.type == TurnType.single) {
    final c = t.cards.single;
    if (c.face == CardFace.dragon) return 15;
    if (c.face == CardFace.mahJong) return 1;
    if (c.face == CardFace.phoenix) {
      return trick == null || trick.cards.isEmpty ? 1 : trick.value.floor();
    }
  }
  if (t.type == TurnType.dog) return 0;
  final v = t.type == TurnType.bomb && t.cards.length > 4
      ? t.value - 20
      : t.value;
  return v.round();
}

// ── API ──────────────────────────────────────────────────────────────────

class Api {
  Api(this.jwt);
  final String jwt;
  final _http = HttpClient();

  Future<Object?> call(String method, String path, [Object? body]) async {
    final req = await _http.openUrl(method, Uri.parse('$_base$path'));
    req.headers
      ..set('Accept', 'application/json')
      ..set('Content-Type', 'application/json')
      ..set('Authorization', 'Bearer $jwt');
    if (body != null) req.write(jsonEncode(body));
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw HttpException('$method $path -> ${res.statusCode}: $text');
    }
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  void close() => _http.close();
}

// ── What seat 0 may read ─────────────────────────────────────────────────

/// The only accessors of a server hand: seat 0's own cards and the public
/// facts. Other seats' `hand_cards` are never read.
class SeatView {
  SeatView(this.hand);
  final Map<String, Object?> hand;

  Map<String, Object?> get ps => hand['play_state']! as Map<String, Object?>;
  List<Map<String, Object?>> get history => [
    for (final e in hand['history']! as List) e as Map<String, Object?>,
  ];

  static List<Map<String, Object?>> _positions(Map<String, Object?> state) => [
    for (final p in state['positions']! as List) p as Map<String, Object?>,
  ];

  static List<int> _ints(Object? l) => [for (final x in l! as List) x as int];

  List<int> myHand([Map<String, Object?>? state]) =>
      _ints(_positions(state ?? ps)[_me]['hand_cards']);

  List<int> myFirstEight() {
    final g =
        (ps['grand_phase_state'] ??
        history.first['state']!.asMap['grand_phase_state'])!;
    return _ints(((g as Map)['first_8s']! as List)[_me]);
  }

  /// Seat 0's 14 cards before the pass, once the Grand decisions are made.
  List<int>? myDealt() {
    for (final e in history) {
      final s = e['state']! as Map<String, Object?>;
      if (s['is_trade_phase'] == true) return myHand(s);
    }
    return null;
  }

  List<int>? mySlate() {
    final s = _positions(ps)[_me]['trade_slate'];
    return s == null ? null : _ints(s);
  }

  /// The card [from] passed to seat 0 (seat 0 sees who gave it), once the
  /// exchange is done.
  int? passedToMe(int from) {
    for (final e in history) {
      final s = e['state']! as Map<String, Object?>;
      if (s['phase'] == 2) {
        final slate = _positions(s)[from]['trade_slate'];
        if (slate == null) return null;
        return (slate as List)[(_me - from - 1) % 4] as int;
      }
    }
    return null;
  }

  bool grandCall(int seat) => _positions(ps)[seat]['grand_bet'] == true;
  int phase() => ps['phase']! as int;
  int active() => ps['active_player']! as int;

  /// Public moves of the play phase, in order.
  List<Map<String, Object?>> moves() => [
    for (final e in history)
      if (e['move'] case final Map<String, Object?> m)
        if ((m['combination']! as Map)['combination_type'] != 13) m,
  ];
}

extension on Object {
  Map<String, Object?> get asMap => this as Map<String, Object?>;
}

// ── Shadow game ──────────────────────────────────────────────────────────

const _ids = ['p0', 'p1', 'p2', 'p3'];
final List<GamePlayer> _players = [
  for (var s = 0; s < 4; s++)
    GamePlayer(id: _ids[s], name: 'S$s', seat: s, type: PlayerType.automated),
];

class Shadow {
  Shadow(this.view, this.random);
  final SeatView view;
  final Random random;
  final engine = GameEngineImpl();
  late final GameEngineState state;

  /// Rebuilds the hand in our engine up to seat 0's next decision.
  void build() {
    final first8 = view.myFirstEight();
    final dealt = view.myDealt();
    final slate = view.mySlate();
    final moves = view.moves();
    final played = List.generate(4, (_) => <int>{});
    for (final m in moves) {
      final c = (m['combination']! as Map)['cards']! as List;
      played[m['position']! as int].addAll(c.cast<int>());
    }
    final toMe = {
      for (final s in [1, 2, 3]) s: ?view.passedToMe(s),
    };
    final exchanged = toMe.length == 3;
    final myGive = slate == null
        ? null
        : {for (var k = 0; k < 3; k++) (_me + k + 1) % 4: slate[k]};

    // Deal: seat 0 exact; the others explain what they played and got.
    final deal = List.generate(4, (_) => <int>[]);
    final gifts = <(int, int), int>{};
    final pool = List<int>.generate(56, (i) => i)..shuffle(random);
    final mine = dealt ?? first8;
    if (!exchanged) {
      pool.removeWhere(mine.contains);
      deal[_me] = mine;
      for (final s in [1, 2, 3]) {
        deal[s] = pool.sublist(0, dealt == null ? 8 : 14);
        pool.removeRange(0, deal[s].length);
      }
    } else {
      final after = List.generate(4, (_) => <int>{});
      for (final s in [1, 2, 3]) {
        after[s]
          ..addAll(played[s])
          ..add(myGive![s]!);
      }
      final first = moves.isEmpty ? null : moves.first['position']! as int;
      final mjMine = mine.contains(3) || toMe.values.contains(3);
      if (first != null && first != _me && !mjMine) after[first].add(3);
      pool.removeWhere(
        (c) =>
            mine.contains(c) ||
            toMe.values.contains(c) ||
            after.any((a) => a.contains(c)),
      );
      for (final s in [1, 2, 3]) {
        final n = 14 - after[s].length;
        after[s].addAll(pool.take(n));
        pool.removeRange(0, n);
      }
      for (final y in [1, 2, 3]) {
        final spare = after[y].where((c) => c != myGive![y]).toList()
          ..shuffle(random);
        for (final x in [1, 2, 3].where((x) => x != y)) {
          gifts[(x, y)] = spare.removeLast();
        }
      }
      deal[_me] = mine;
      for (final x in [1, 2, 3]) {
        final h = after[x].toList()..remove(myGive![x]);
        for (final y in [1, 2, 3].where((y) => y != x)) {
          h
            ..remove(gifts[(y, x)])
            ..add(gifts[(x, y)]!);
        }
        h.add(toMe[x]!);
        deal[x] = h;
      }
    }
    // First eight stay first eight for seat 0; pad to 14 from what is left.
    final rest = List<int>.generate(56, (i) => i)
      ..removeWhere((c) => deal.any((d) => d.contains(c)))
      ..shuffle(random);
    for (var s = 0; s < 4; s++) {
      while (deal[s].length < 14) {
        deal[s].add(rest.removeLast());
      }
    }
    final mineOrdered = [
      ...first8,
      ...deal[_me].where((c) => !first8.contains(c)),
    ];
    deal[_me] = mineOrdered;

    state = engine.createGame(gameId: 'te', players: _players);
    engine.startGame(state);
    for (var s = 0; s < 4; s++) {
      state.hands[_ids[s]] = [for (final c in deal[s].take(8)) cardOf(c)];
      state.reservedHands[_ids[s]] = [
        for (final c in deal[s].skip(8)) cardOf(c),
      ];
    }

    // Grand decisions and the exchange.
    while (true) {
      final req = AgentDecisions.next(engine, state);
      if (req == null) break;
      final seat = int.parse(req.playerId.substring(1));
      switch (req) {
        case GrandTichuRequest():
          if (seat == _me && dealt == null) return;
          engine.applyAction(
            state,
            GrandTichuDecisionAction(
              playerId: req.playerId,
              call: view.grandCall(seat),
            ),
          );
        case SchupfRequest():
          final to = seat == _me
              ? myGive
              : exchanged
              ? {
                  for (final r in [1, 2, 3, 0].where((r) => r != seat))
                    r: r == _me ? toMe[seat]! : gifts[(seat, r)]!,
                }
              : null;
          if (seat == _me && to == null) return;
          final hand = state.hands[req.playerId]!;
          Card pick(int r) => to == null
              ? hand[r % hand.length]
              : hand.firstWhere((c) => idOf(c) == to[r]);
          engine.applyAction(
            state,
            SchupfAction(
              playerId: req.playerId,
              toLeft: pick((seat + 1) % 4),
              toPartner: pick((seat + 2) % 4),
              toRight: pick((seat + 3) % 4),
            ),
          );
        case SchupfReceiptRequest():
          engine.applyAction(
            state,
            AcknowledgeSchupfAction(playerId: req.playerId),
          );
        case PreSchupfTichuRequest():
          break;
        case TurnRequest() || DragonGiveRequest():
          _replayPlay(moves, played);
          return;
      }
    }
  }

  void _replayPlay(List<Map<String, Object?>> moves, List<Set<int>> played) {
    for (var i = 0; i < moves.length; i++) {
      final m = moves[i];
      final seat = m['position']! as int;
      final id = _ids[seat];
      final comb = m['combination']! as Map;
      final type = comb['combination_type']! as int;
      final cards = (comb['cards']! as List).cast<int>();
      switch (type) {
        case _bet:
          engine.applyAction(state, CallTichuAction(playerId: id));
        case _makeWish:
          break; // folded into the Mah Jong play
        case _giveDragon:
          engine.applyAction(
            state,
            GiveDragonAction(
              playerId: id,
              targetPlayerId: _ids[m['give_dragon_pos']! as int],
            ),
          );
        case _pass when m['win_trick'] == true:
          break; // the server's trick-taking step; our engine ends tricks
        case _pass:
          _apply(seat, PassAction(playerId: id), played);
        default:
          var wish = CardFace.none;
          if (cards.contains(3)) {
            for (final n in moves.skip(i + 1)) {
              final nc = n['combination']! as Map;
              if (n['position'] == seat &&
                  nc['combination_type'] == _makeWish &&
                  n['wish_rank'] != null) {
                wish = _faces[(n['wish_rank']! as int) - 2];
                break;
              }
            }
          }
          final turn = _matchTurn(
            seat,
            cards,
            type,
            comb['rank']! as int,
            played,
          );
          _apply(
            seat,
            PlayTurnAction(playerId: id, cards: turn.cards, inputWish: wish),
            played,
          );
      }
    }
  }

  /// Our engine's turn for a server play: same cards and type, the Phoenix
  /// read as the server's rank.
  TichuTurn _matchTurn(
    int seat,
    List<int> cards,
    int type,
    int rank,
    List<Set<int>> played,
  ) {
    final want = [...cards]..sort();
    for (final wishFree in [false, true]) {
      final deck = wishFree
          ? DeckState(state.deck.turn, CardFace.none)
          : state.deck;
      final hand = state.hands[_ids[seat]]!;
      for (final t in generateLegalTurns(deck, List.of(hand))) {
        if (typeOf(t) == type && _eq(idsOf(t.cards), want)) {
          if (rankOf(t, state.deck.turn) == rank || !cards.contains(0)) {
            return t;
          }
        }
      }
    }
    // The generator lists one variant; the engine reads the cards itself.
    return getTurn([for (final c in cards) cardOf(c)]);
  }

  static bool _eq(List<int> a, List<int> b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i] == b[i]).every((x) => x);

  /// Applies another seat's move; when its guessed hand could fulfil the
  /// wish it did not fulfil, swaps hidden cards until it could not.
  void _apply(int seat, GameAction action, List<Set<int>> played) {
    for (var tries = 0; tries < 400; tries++) {
      try {
        engine.applyAction(state, action);
        return;
      } on IllegalActionException {
        if (seat == _me || state.deck.wish == CardFace.none) rethrow;
        _swapWish(seat, played);
      }
    }
    // No guess explains it: take the move as a fact.
    final wish = state.deck.wish;
    state.deck = DeckState(state.deck.turn, CardFace.none)
      ..currentWinner = state.deck.currentWinner
      ..cardStack = state.deck.cardStack;
    engine.applyAction(state, action);
    if (state.deck.wish == CardFace.none && action is! PlayTurnAction) {
      state.deck = DeckState(state.deck.turn, wish)
        ..currentWinner = state.deck.currentWinner
        ..cardStack = state.deck.cardStack;
    }
  }

  void _swapWish(int seat, List<Set<int>> played) {
    final hand = state.hands[_ids[seat]]!;
    final free = hand.where((c) => !played[seat].contains(idOf(c))).toList();
    final wished = free.where((c) => c.face == state.deck.wish).toList();
    final pick = wished.isNotEmpty ? wished : free;
    final others = [1, 2, 3].where((s) => s != seat).toList();
    final y = others[random.nextInt(others.length)];
    final theirs = state.hands[_ids[y]]!
        .where((c) => !played[y].contains(idOf(c)) && c.face != state.deck.wish)
        .toList();
    if (pick.isEmpty || theirs.isEmpty) return;
    final c = pick[random.nextInt(pick.length)];
    final d = theirs[random.nextInt(theirs.length)];
    hand
      ..remove(c)
      ..add(d);
    state.hands[_ids[y]]!
      ..remove(d)
      ..add(c);
  }
}

// ── The bot ──────────────────────────────────────────────────────────────

class Bot {
  Bot(this.config, this.searcher);
  final BotConfig config;
  final EndgameSearcher searcher;

  PlayerAgent get agent => config.build(_ids[_me]);
}

Future<Bot> loadBot(Map<String, String> flags) async {
  Future<LoadedNet?> net(String key) async {
    final path = flags[key];
    if (path == null) return null;
    return LoadedNet.fromBytes(
      Uint8List.fromList(await File(path).readAsBytes()),
    );
  }

  const search = EndgameSearch(
    maxCards: 12,
    solveOneOnOne: true,
    beliefWorlds: true,
  );
  final base = BotConfig(
    play: await net('nn-policy'),
    schupf: await net('schupf-net'),
    schupfExtended: true,
  );
  final belief = await net('belief-net');
  return Bot(
    base.withEndgameSearch(search),
    EndgameSearcher(
      rolloutAgent: (id, _) => base.build(id),
      belief: belief == null ? null : BeliefModel(belief.network),
    ),
  );
}

// ── Playing a table ──────────────────────────────────────────────────────

Future<void> act(
  Api api,
  String table,
  SeatView view,
  Map<String, Object?> move,
) async {
  await api.call('POST', '/api/table/$table/act', {
    'position': _me,
    'bet': false,
    'wish_rank': null,
    'give_dragon_pos': null,
    'win_trick': false,
    ...move,
    'expected_index': view.history.length,
  });
}

/// Seat 0's decision, if it has one now. Returns true when it acted.
Future<bool> decide(
  Api api,
  String table,
  SeatView view,
  Bot bot,
  Random random,
  CardFace pendingWish,
  void Function(CardFace) setWish,
) async {
  final ps = view.ps;
  if (ps['is_hand_over'] == true) return false;
  final grand = ps['grand_phase_state'] as Map?;
  if (view.phase() == 0 && grand != null) {
    final choices = grand['grand_bet_choices'] as List;
    if (choices[_me] != null) return false;
    final shadow = Shadow(view, random)..build();
    final call = await bot.agent.shouldCallGrandTichu(
      shadow.engine.buildSnapshot(shadow.state),
    );
    await api.call('POST', '/api/table/$table/choose_grand_bet', {
      'position': _me,
      'bet': call,
    });
    return true;
  }
  if (ps['is_trade_phase'] == true) {
    if (view.mySlate() != null) return false;
    final shadow = Shadow(view, random)..build();
    final s = await bot.agent.selectSchupfCards(
      shadow.engine.buildSnapshot(shadow.state),
    );
    await api.call('POST', '/api/table/$table/choose_trade', {
      'position': _me,
      'trade_slate': [idOf(s.toLeft), idOf(s.toPartner), idOf(s.toRight)],
    });
    return true;
  }
  if (view.active() != _me) return false;
  if (ps['make_wish'] == true) {
    await act(api, table, view, {
      'combination': {
        'combination_type': _makeWish,
        'cards': <int>[],
        'rank': 0,
      },
      'wish_rank': pendingWish == CardFace.none ? null : _rankOf(pendingWish),
    });
    setWish(CardFace.none);
    return true;
  }
  // A finished trick (everyone passed on our combination, or our partner's
  // Dog gave us the lead) is collected by the server after its bomb
  // window; nobody may act meanwhile.
  final winner = ps['winning_player'] as int?;
  final winning = ps['winning_combination'] as Map?;
  if (ps['give_dragon'] != true &&
      winner != null &&
      (winner == _me || winning?['combination_type'] == _dog)) {
    return false;
  }
  final shadow = Shadow(view, random)..build();
  final state = shadow.state;
  final snapshot = shadow.engine.buildSnapshot(state);
  final agent = bot.agent;
  final req = AgentDecisions.next(shadow.engine, state);
  if (ps['give_dragon'] == true) {
    if (req is! DragonGiveRequest || req.playerId != _ids[_me]) {
      throw StateError('Shadow has no Dragon gift pending: $req');
    }
    final resolved = await AgentDecisions.resolve(req, agent, snapshot, state);
    var gift = resolved! as GiveDragonAction;
    gift = await bot.searcher.refineDragonGift(
      state: state,
      agent: agent,
      chosen: gift,
    ) as GiveDragonAction;
    await act(api, table, view, {
      'combination': {
        'combination_type': _giveDragon,
        'cards': <int>[],
        'rank': 0,
      },
      'give_dragon_pos': int.parse(gift.targetPlayerId.substring(1)),
    });
    return true;
  }
  if (req is! TurnRequest || req.playerId != _ids[_me]) {
    throw StateError('Shadow is not at our turn: $req');
  }
  var action = await agent.selectAction(snapshot);
  if (action is PlayTurnAction || action is PassAction) {
    action = await bot.searcher.refine(
      state: state,
      agent: agent,
      chosen: action,
    );
  }
  switch (action) {
    case CallTichuAction():
      await act(api, table, view, {
        'combination': {'combination_type': _bet, 'cards': <int>[], 'rank': 0},
        'bet': true,
      });
    case PassAction():
      await act(api, table, view, {
        'combination': {'combination_type': _pass, 'cards': <int>[], 'rank': 0},
      });
    case PlayTurnAction(:final cards, :final inputWish):
      final turn = getTurn(List.of(cards));
      await act(api, table, view, {
        'combination': {
          'combination_type': typeOf(turn),
          'cards': idsOf(cards),
          'rank': rankOf(turn, state.deck.turn),
        },
      });
      if (cards.any((c) => c.face == CardFace.mahJong)) setWish(inputWish);
    default:
      throw StateError('Unexpected action $action');
  }
  return true;
}

Future<Map<String, Object?>> playGame(
  Api api,
  Bot bot,
  String strength,
  Random random, {
  String? resume,
}) async {
  final table =
      resume ??
      ((await api.call('POST', '/api/table/new', {}))! as Map)['id'] as String;
  if (resume == null) await _setUp(api, table, strength);
  stderr.writeln('table $table');
  return _play(api, table, bot, random);
}

Future<void> _setUp(Api api, String table, String strength) async {
  for (final seat in [1, 2, 3]) {
    await api.call('POST', '/api/table/$table/addBot', {
      'seat': seat,
      'strength': strength,
    });
  }
  await api.call('POST', '/api/table/$table/update_team_conventions', {
    'team': 'ns',
    'conventions': {'opp_trade_convention': 0, 'partner_trade_convention': 3},
  });
  await api.call('POST', '/api/table/$table/start', {});
}

Future<Map<String, Object?>> _play(
  Api api,
  String table,
  Bot bot,
  Random random,
) async {
  var wish = CardFace.none;
  var idle = 0;
  while (true) {
    final t = (await api.call('GET', '/api/table/$table'))! as Map;
    final game = t['game']! as Map;
    final hands = game['game_hands']! as List;
    if (hands.isEmpty) {
      await Future<void>.delayed(const Duration(seconds: 1));
      continue;
    }
    final view = SeatView(hands.last as Map<String, Object?>);
    final ps = view.ps;
    if (ps['is_hand_over'] == true) {
      // Scores are per hand; the game ends at status 3 (complete).
      var ns = 0;
      var ew = 0;
      for (final h in hands) {
        final hp = (h as Map)['play_state']! as Map;
        ns += hp['ns_score']! as int;
        ew += hp['ew_score']! as int;
      }
      stderr.writeln('hand ${hands.length}: $ns - $ew');
      if (game['status'] == 3) {
        return {'table': table, 'ns': ns, 'ew': ew, 'hands': hands.length};
      }
      await api.call('POST', '/api/table/$table/nextHand', {});
      continue;
    }
    bool acted;
    try {
      acted = await decide(api, table, view, bot, random, wish, (w) {
        wish = w;
      });
    } on HttpException catch (e) {
      // The game moved on while we thought (a trick ended, a bot played):
      // the server refuses the stale move; decide again on the new state.
      if (!e.message.contains('Stale submission')) rethrow;
      continue;
    }
    if (acted) {
      idle = 0;
    } else {
      idle++;
      if (idle > 600) throw StateError('Table $table stalled');
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
  }
}

Future<void> main(List<String> args) async {
  final flags = <String, String>{
    for (final a in args)
      if (a.startsWith('--') && a.contains('='))
        a.substring(2, a.indexOf('=')): a.substring(a.indexOf('=') + 1),
  };
  final games = int.parse(flags['games'] ?? '1');
  final strength = flags['strength'] ?? 'Grandmaster';
  final jwt = File(flags['jwt-file']!).readAsStringSync().trim();
  final out = File(flags['out'] ?? 'arena/results/tichuengine.jsonl');
  final api = Api(jwt);
  final bot = await loadBot(flags);
  final random = Random(int.parse(flags['seed'] ?? '1'));
  try {
    for (var g = 0; g < games; g++) {
      final result = await playGame(
        api,
        bot,
        strength,
        random,
        resume: g == 0 ? flags['resume'] : null,
      );
      final row = {
        ...result,
        'strength': strength,
        'won': (result['ns']! as int) > (result['ew']! as int),
        'at': DateTime.now().toUtc().toIso8601String(),
      };
      out.writeAsStringSync('${jsonEncode(row)}\n', mode: FileMode.append);
      stdout.writeln(jsonEncode(row));
    }
  } finally {
    api.close();
  }
}
