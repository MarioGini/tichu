import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/bot_config.dart';
import 'package:tichu/agents/endgame_search.dart';
import 'package:tichu/agents/partner_convention.dart';
import 'package:tichu/agents/shipped_bots.dart';
import 'package:tichu/game/agent_decisions.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/scoring/score_state.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';
import 'package:tichu/game/turn/tichu_data.dart';

const _players = [
  GamePlayer(id: 'p1', name: 'P1', seat: 0, type: PlayerType.automated),
  GamePlayer(id: 'p2', name: 'P2', seat: 1, type: PlayerType.automated),
  GamePlayer(id: 'p3', name: 'P3', seat: 2, type: PlayerType.automated),
  GamePlayer(id: 'p4', name: 'P4', seat: 3, type: PlayerType.automated),
];

Card _c(CardFace f, [CardColor color = CardColor.black]) => Card(f, switch (f) {
  CardFace.mahJong ||
  CardFace.dog ||
  CardFace.phoenix ||
  CardFace.dragon => CardColor.special,
  _ => color,
});

List<Card> _hand(List<CardFace> faces) => [
  for (var i = 0; i < faces.length; i++) _c(faces[i], CardColor.values[i % 4]),
];

const PartnerConvention _rule = PartnerConvention.twoHcOdd;

Set<CardFace>? _allowedFaces(
  List<Card> hand, {
  bool selfCalled = false,
  bool partnerCalled = false,
  bool rightGrand = false,
}) => _rule
    .allowedPartnerCards(
      hand,
      selfCalled: selfCalled,
      partnerCalled: partnerCalled,
      rightGrand: rightGrand,
    )
    ?.map((i) => hand[i].face)
    .toSet();

/// Partner passes of the [config] bots in [rounds] rounds, with the
/// passer's hand before the exchange and the calls at that time.
Future<List<(List<Card> hand, SchupfAction pass, Map<String, TichuCall> calls)>>
_passes(BotConfig config, int rounds) async {
  final engine = GameEngineImpl();
  final state = engine.createGame(
    gameId: 'convention_test',
    players: _players,
    targetScore: 100000,
  );
  engine.startGame(state);
  final agents = {for (final p in _players) p.id: config.build(p.id)};
  final out = <(List<Card>, SchupfAction, Map<String, TichuCall>)>[];
  var round = 0;
  while (round < rounds) {
    if (state.scoreTracker.state.roundComplete) {
      engine.startNewRound(state);
      round++;
      continue;
    }
    final request = AgentDecisions.next(engine, state);
    if (request == null) fail('no pending decision');
    final snap = engine.buildSnapshot(state);
    final action = await AgentDecisions.resolve(
      request,
      agents[request.playerId]!,
      snap,
      state,
    );
    if (action is SchupfAction) {
      out.add((
        List<Card>.from(state.hands[action.playerId]!),
        action,
        Map.of(snap.scoreState.tichuCalls),
      ));
    }
    if (action != null) engine.applyAction(state, action);
  }
  return out;
}

void _expectConforming(
  List<(List<Card>, SchupfAction, Map<String, TichuCall>)> passes,
) {
  var checked = 0;
  for (final (hand, pass, calls) in passes) {
    final seat = _players.firstWhere((p) => p.id == pass.playerId).seat;
    String at(int o) => _players[(seat + o) % 4].id;
    bool called(String id) => (calls[id] ?? TichuCall.none) != TichuCall.none;
    final allowed = _rule.allowedPartnerCards(
      hand,
      selfCalled: called(pass.playerId),
      partnerCalled: called(at(2)),
      rightGrand: calls[at(3)] == TichuCall.grandTichu,
    );
    if (allowed == null) continue;
    checked++;
    expect(
      allowed.map((i) => hand[i]),
      contains(pass.toPartner),
      reason: '$hand -> ${pass.toPartner.face}',
    );
  }
  expect(checked, greaterThan(passes.length ~/ 2));
}

void main() {
  group('2+ HC Odd: what may go to the partner', () {
    final low = [
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
    ];
    test('0 high cards: an even card', () {
      expect(_allowedFaces(_hand([...low, CardFace.king, CardFace.dog])), {
        CardFace.two,
        CardFace.four,
        CardFace.six,
        CardFace.eight,
        CardFace.ten,
        CardFace.queen,
      });
    });
    test('1 high card: that card', () {
      expect(_allowedFaces(_hand([...low, CardFace.phoenix, CardFace.dog])), {
        CardFace.phoenix,
      });
    });
    test('2+ high cards: odd, the Mahjong or the Dog', () {
      expect(
        _allowedFaces(
          _hand([
            ...low.take(9),
            CardFace.ace,
            CardFace.dragon,
            CardFace.mahJong,
            CardFace.dog,
          ]),
        ),
        {
          CardFace.three,
          CardFace.five,
          CardFace.seven,
          CardFace.nine,
          CardFace.mahJong,
          CardFace.dog,
        },
      );
    });
    test('right opponent called Grand: odd or a high card with 1 HC', () {
      expect(
        _allowedFaces(
          _hand([...low, CardFace.ace, CardFace.dog]),
          rightGrand: true,
        ),
        {
          CardFace.three,
          CardFace.five,
          CardFace.seven,
          CardFace.nine,
          CardFace.jack,
          CardFace.dog,
          CardFace.ace,
        },
      );
    });
    test('partner called: a high card; I called: no constraint', () {
      final hand = _hand([...low, CardFace.ace, CardFace.dragon]);
      expect(_allowedFaces(hand, partnerCalled: true), {
        CardFace.ace,
        CardFace.dragon,
      });
      expect(_allowedFaces(hand, selfCalled: true), isNull);
    });
    test('free never constrains', () {
      expect(
        PartnerConvention.free.allowedPartnerCards(
          _hand([...low, CardFace.ace, CardFace.dog]),
          selfCalled: false,
          partnerCalled: false,
          rightGrand: false,
        ),
        isNull,
      );
    });
  });

  group('2+ HC Odd: what the partner card promises', () {
    (int, int)? promise(CardFace f, {bool grand = false}) =>
        _rule.promisedOtherHighCards(_c(f), partnersRightGrand: grand);
    test('even: none kept, high card: no other, odd: 2+', () {
      expect(promise(CardFace.queen), (0, 0));
      expect(promise(CardFace.ace), (0, 0));
      expect(promise(CardFace.king), (2, highCardsInDeck));
      expect(promise(CardFace.dog), (2, highCardsInDeck));
      expect(promise(CardFace.mahJong), (2, highCardsInDeck));
    });
    test("partner's right opponent called Grand", () {
      expect(promise(CardFace.ace, grand: true), isNull);
      expect(promise(CardFace.three, grand: true), (1, highCardsInDeck));
      expect(promise(CardFace.two, grand: true), (0, 0));
    });
  });

  test('enforceHighCardPromise swaps high cards into the range', () {
    final partner = _hand([CardFace.ace, CardFace.dragon, CardFace.two]);
    final left = _hand([CardFace.three, CardFace.four]);
    final right = _hand([CardFace.five, CardFace.phoenix]);
    final deal = {'partner': partner, 'left': left, 'right': right};
    enforceHighCardPromise(
      deal,
      partnerId: 'partner',
      opponentIds: ['left', 'right'],
      partnerKept: 2,
      range: (0, 0),
      isPinned: (_) => false,
      random: Random(1),
    );
    expect(deal['partner']!.where(isHighCard), isEmpty);
    expect(deal.values.expand((h) => h).where(isHighCard).length, 3);

    enforceHighCardPromise(
      deal,
      partnerId: 'partner',
      opponentIds: ['left', 'right'],
      partnerKept: 0,
      range: (2, highCardsInDeck),
      isPinned: (c) => c.face == CardFace.phoenix,
      random: Random(1),
    );
    // Two of Ace, Dragon move back; the pinned Phoenix stays.
    expect(deal['partner']!.where(isHighCard).length, 2);
    expect(deal['right']!.any((c) => c.face == CardFace.phoenix), isTrue);
  });

  test('heuristic bots pass to the partner by the convention', () async {
    _expectConforming(
      await _passes(BotConfig.heuristic.withPartnerConvention(_rule), 40),
    );
  });

  test('schupf net passes to the partner by the convention', () async {
    final config = BotConfig(
      schupf: LoadedNet.fromBytes(
        File(ShippedBots.schupfAsset).readAsBytesSync(),
      ),
      schupfExtended: ShippedBots.schupfExtended,
      partnerConvention: _rule,
    );
    _expectConforming(await _passes(config, 40));
  });

  test("re-dealt worlds keep the partner's promise", () async {
    final engine = GameEngineImpl();
    final state = engine.createGame(
      gameId: 'convention_worlds',
      players: _players,
      targetScore: 100000,
    );
    engine.startGame(state);
    final agents = <String, PlayerAgent>{
      for (final p in _players)
        p.id: BotConfig.heuristic.withPartnerConvention(_rule).build(p.id),
    };
    var checked = 0;
    for (var steps = 0; checked < 30 && steps < 20000; steps++) {
      if (state.scoreTracker.state.roundComplete) {
        engine.startNewRound(state);
        continue;
      }
      final request = AgentDecisions.next(engine, state);
      if (request == null) fail('no pending decision');
      if (request is TurnRequest && state.roundLog.isEmpty) {
        final me = request.playerId;
        final seat = _players.firstWhere((p) => p.id == me).seat;
        final partner = _players[(seat + 2) % 4].id;
        final calls = state.scoreTracker.state.tichuCalls;
        final passed = state.completedSchupfSelections[partner]!.toPartner;
        final range = _rule.promisedOtherHighCards(
          passed,
          partnersRightGrand:
              calls[_players[(seat + 1) % 4].id] == TichuCall.grandTichu,
        );
        // Only rounds where the real hands keep the promise (nobody
        // called, no opponent passed the partner a high card).
        // What the partner received: mine, and from each opponent.
        final sel = state.completedSchupfSelections;
        final fromOpponents = [
          sel[_players[(seat + 1) % 4].id]!.toRight,
          sel[_players[(seat + 3) % 4].id]!.toLeft,
        ];
        final receipts = [sel[me]!.toPartner, ...fromOpponents];
        bool received(Card c) =>
            receipts.any((r) => r.face == c.face && r.color == c.color);
        final own = state.hands[partner]!
            .where((c) => isHighCard(c) && !received(c))
            .length;
        final opponentGaveHigh = fromOpponents.any(isHighCard);
        if (calls.values.every((c) => c == TichuCall.none) &&
            range != null &&
            !opponentGaveHigh &&
            own >= range.$1 &&
            own <= range.$2) {
          final random = Random(steps);
          for (var w = 0; w < 20; w++) {
            final deal = dealUnseen(state, me, random, convention: _rule);
            final kept = deal[partner]!.where(isHighCard).length;
            final mine = state.completedSchupfSelections[me]!.toPartner;
            final keptOwn = kept - (isHighCard(mine) ? 1 : 0);
            expect(keptOwn, inInclusiveRange(range.$1, range.$2));
          }
          checked++;
        }
      }
      final action = await AgentDecisions.resolve(
        request,
        agents[request.playerId]!,
        engine.buildSnapshot(state),
        state,
      );
      if (action != null) engine.applyAction(state, action);
    }
    expect(checked, 30);
  });
}
