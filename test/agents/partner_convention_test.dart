import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/endgame_search.dart';
import 'package:tichu/agents/nn/mlp.dart';
import 'package:tichu/agents/nn/nn_schupf_strategy.dart';
import 'package:tichu/agents/partner_convention.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/agent_decisions.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/round_log.dart';
import 'package:tichu/game/scoring/score_state.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'ai_test_fixtures.dart';

Card _c(CardFace f, [CardColor c = CardColor.black]) => Card(f, c);

const PartnerConvention _convention = PartnerConvention.twoHighCardsOdd;

void main() {
  group('2+HC Odd', () {
    final low = [
      for (final f in [CardFace.two, CardFace.three, CardFace.four]) _c(f),
    ];
    test('0 high cards: pass even', () {
      final hand = [...low, _c(CardFace.queen)];
      expect(_convention.conforms(hand, _c(CardFace.two)), isTrue);
      expect(_convention.conforms(hand, _c(CardFace.queen)), isTrue);
      expect(_convention.conforms(hand, _c(CardFace.three)), isFalse);
    });
    test('1 high card: pass it', () {
      final hand = [...low, _c(CardFace.dragon)];
      expect(_convention.conforms(hand, _c(CardFace.dragon)), isTrue);
      expect(_convention.conforms(hand, _c(CardFace.two)), isFalse);
      expect(_convention.conforms(hand, _c(CardFace.three)), isFalse);
    });
    test('2+ high cards: pass odd (Mah Jong and Dog count as odd)', () {
      final hand = [...low, _c(CardFace.ace), _c(CardFace.phoenix)];
      expect(_convention.conforms(hand, _c(CardFace.three)), isTrue);
      expect(_convention.conforms(hand, _c(CardFace.mahJong)), isTrue);
      expect(_convention.conforms(hand, _c(CardFace.dog)), isTrue);
      expect(_convention.conforms(hand, _c(CardFace.four)), isFalse);
      expect(_convention.conforms(hand, _c(CardFace.ace)), isFalse);
    });
    test('promises', () {
      expect(_convention.promise(_c(CardFace.king)), HighCardPromise.twoOrMore);
      expect(_convention.promise(_c(CardFace.ten)), HighCardPromise.zero);
      expect(_convention.promise(_c(CardFace.ace)), HighCardPromise.zero);
      expect(
        PartnerConvention.none.promise(_c(CardFace.king)),
        HighCardPromise.none,
      );
      expect(PartnerConvention.keeps(HighCardPromise.twoOrMore, 1), isFalse);
      expect(PartnerConvention.keeps(HighCardPromise.zero, 0), isTrue);
    });
    test('off when the team called Grand Tichu', () {
      expect(
        _convention.appliesTo(TichuCall.none, TichuCall.grandTichu),
        isFalse,
      );
      expect(_convention.appliesTo(TichuCall.tichu, TichuCall.none), isTrue);
    });
    test('parsing', () {
      expect(PartnerConvention.tryParse('2hc-odd'), _convention);
      expect(PartnerConvention.tryParse('bogus'), isNull);
    });
  });

  test('high cards passed to the opponents do not count as kept', () {
    // Ace + Dragon, the Ace to an opponent: one high card kept, so the
    // partner must get the Dragon, not an odd card.
    final hand = [
      _c(CardFace.ace),
      _c(CardFace.dragon),
      _c(CardFace.seven),
      _c(CardFace.two),
    ];
    final opponents = [_c(CardFace.ace), _c(CardFace.two)];
    expect(
      _convention.conforms(hand, _c(CardFace.seven), toOpponents: opponents),
      isFalse,
    );
    expect(
      _convention.conforms(hand, _c(CardFace.dragon), toOpponents: opponents),
      isTrue,
    );
    expect(_convention.conforms(hand, _c(CardFace.seven)), isTrue);
  });

  test('a promise broken by played cards cannot be read', () {
    expect(PartnerConvention.keepsSoFar(HighCardPromise.zero, 1), isFalse);
    expect(PartnerConvention.keepsSoFar(HighCardPromise.atMostOne, 1), isTrue);
    expect(PartnerConvention.keepsSoFar(HighCardPromise.twoOrMore, 0), isTrue);
  });

  test('parity: never a forced high card', () {
    const p = PartnerConvention.parity;
    final two = [_c(CardFace.ace), _c(CardFace.dragon), _c(CardFace.two)];
    final one = [_c(CardFace.ace), _c(CardFace.two), _c(CardFace.three)];
    expect(p.conforms(two, _c(CardFace.three)), isTrue);
    expect(p.conforms(two, _c(CardFace.two)), isFalse);
    expect(p.conforms(one, _c(CardFace.two)), isTrue);
    expect(p.conforms(one, _c(CardFace.ace)), isFalse);
    expect(p.conforms(one, _c(CardFace.three)), isFalse);
    expect(p.promise(_c(CardFace.nine)), HighCardPromise.twoOrMore);
    expect(p.promise(_c(CardFace.eight)), HighCardPromise.atMostOne);
    expect(PartnerConvention.keeps(HighCardPromise.atMostOne, 1), isTrue);
    expect(PartnerConvention.keeps(HighCardPromise.atMostOne, 2), isFalse);
    expect(PartnerConvention.tryParse('parity'), p);
  });

  test('the schupf net passes a conforming card to the partner', () async {
    final hand = [
      _c(CardFace.two),
      _c(CardFace.three),
      _c(CardFace.four, CardColor.red),
      _c(CardFace.five),
      _c(CardFace.six),
      _c(CardFace.seven),
      _c(CardFace.eight),
      _c(CardFace.nine),
      _c(CardFace.ten),
      _c(CardFace.jack),
      _c(CardFace.queen),
      _c(CardFace.king),
      _c(CardFace.ace),
      _c(CardFace.dragon),
    ];
    for (final seed in [1, 2, 3, 4, 5, 6]) {
      final network = Mlp(layerSizes: [SchupfFeatures.size, 8, 1], seed: seed);
      final snap = aiSnapshot(myHand: hand, otherHands: const {});
      final pass = await NnSchupfStrategy(
        network: network,
        convention: _convention,
      ).selectSchupfCards(snap, aiTestSelfId);
      expect(
        _convention.conforms(hand, pass.toPartner),
        isTrue,
        reason: 'seed $seed passed ${pass.toPartner.face}',
      );
    }
  });

  test('search worlds keep the partner promise', () async {
    final engine = GameEngineImpl(random: Random(5));
    const players = [
      GamePlayer(id: 'p1', name: 'P1', seat: 0, type: PlayerType.automated),
      GamePlayer(id: 'p2', name: 'P2', seat: 1, type: PlayerType.automated),
      GamePlayer(id: 'p3', name: 'P3', seat: 2, type: PlayerType.automated),
      GamePlayer(id: 'p4', name: 'P4', seat: 3, type: PlayerType.automated),
    ];
    final state = engine.createGame(gameId: 'conv', players: players);
    engine.startGame(state);
    final agents = {for (final p in players) p.id: SmartAiAgent(p.id)};
    while (true) {
      final request = AgentDecisions.next(engine, state)!;
      if (request is TurnRequest) break;
      final action = await AgentDecisions.resolve(
        request,
        agents[request.playerId]!,
        engine.buildSnapshot(state),
        state,
      );
      if (action != null) engine.applyAction(state, action);
    }
    // A player whose team called no Grand Tichu (the convention is off
    // otherwise); their partner passed them an odd card: 2+ high cards.
    final calls = state.scoreTracker.state.tichuCalls;
    bool grand(String id) => calls[id] == TichuCall.grandTichu;
    final actor = players.firstWhere(
      (p) => !grand(p.id) && !grand(players[(p.seat + 2) % 4].id),
    );
    final partner = players[(actor.seat + 2) % 4].id;
    final real = state.completedSchupfSelections[partner]!;
    state.completedSchupfSelections[partner] = SchupfAction(
      playerId: partner,
      toLeft: real.toLeft,
      toPartner: _c(CardFace.three, CardColor.green),
      toRight: real.toRight,
    );
    final accept = conventionAccept(state, actor.id, _convention)!;
    final gift = PartnerConvention.isHighCard(
      state.completedSchupfSelections[actor.id]!.toPartner,
    );
    final random = Random(1);
    var kept = 0;
    for (var i = 0; i < 40; i++) {
      final deal = dealUnseen(state, actor.id, random, accept: accept);
      final high = PartnerConvention.highCards(deal[partner]!) - (gift ? 1 : 0);
      expect(accept(deal), high >= 2);
      if (high >= 2) kept++;
    }
    // Rejection sampling almost always finds such a deal.
    expect(kept, greaterThan(36));
    expect(
      () => dealUnseen(state, actor.id, random, accept: accept, tries: 0),
      throwsArgumentError,
    );
    // Partner promised 0 high cards but already played one (an opponent
    // passed it): the promise cannot be read, so no filter.
    state.completedSchupfSelections[partner] = SchupfAction(
      playerId: partner,
      toLeft: real.toLeft,
      toPartner: _c(CardFace.two, CardColor.green),
      toRight: real.toRight,
    );
    final roundLog = state.roundLog;
    roundLog.add(
      RoundLogEntry(
        playerId: partner,
        cards: [_c(CardFace.ace, CardColor.blue)],
        trickType: TurnType.empty,
        trickValue: 0,
        trickWinner: '',
      ),
    );
    expect(conventionAccept(state, actor.id, _convention), isNull);
    roundLog.removeLast();
    // A Grand Tichu call in the team switches the convention off.
    calls[partner] = TichuCall.grandTichu;
    expect(conventionAccept(state, actor.id, _convention), isNull);
    expect(conventionAccept(state, actor.id, PartnerConvention.none), isNull);
  });
}
