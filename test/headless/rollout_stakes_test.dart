import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/engine_state.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/headless/rollout_stakes.dart';

import '../game/turn/engine/engine_test_fixtures.dart';
import '../utils/test_game_fixtures.dart';

List<Card> _cards(final int n, [final CardColor color = CardColor.red]) => [
  for (var i = 0; i < n; i++) fxCard(CardFace.values[2 + i % 13], color),
];

/// Seat 0 to move with [own] cards, the others with [others] cards each
/// (left, partner, right), following a single unless [lead].
({GameEngineImpl engine, GameEngineState state}) _setup({
  final int own = 10,
  final List<int> others = const [10, 10, 10],
  final bool lead = false,
}) {
  final engine = GameEngineImpl();
  final state = fxState(
    phase: GamePhase.play,
    deck: lead
        ? DeckState(TichuTurn(TurnType.empty, const []), CardFace.none)
        : DeckState(
            TichuTurn(TurnType.single, [
              fxCard(CardFace.three, CardColor.black),
            ]),
            CardFace.none,
          ),
    hands: {
      testHumanId: _cards(own),
      testOpponentLeftId: _cards(others[0], CardColor.blue),
      testOpponentPartnerId: _cards(others[1], CardColor.green),
      testOpponentRightId: _cards(others[2], CardColor.black),
    },
  );
  if (!lead) state.lastPlayedBy = testOpponentRightId;
  return (engine: engine, state: state);
}

GameSnapshot _snap(final ({GameEngineImpl engine, GameEngineState state}) s) =>
    s.engine.buildSnapshot(s.state);

void main() {
  group('stakes classifier', () {
    test('quiet middle game is low', () {
      final snap = _snap(_setup());
      expect(stakesReasons(snap, testHumanId), isEmpty);
      expect(classifyStakes(snap, testHumanId), RolloutStakes.low);
    });

    test('a lead is mid', () {
      final snap = _snap(_setup(lead: true));
      expect(stakesReasons(snap, testHumanId), {StakesReason.lead});
      expect(classifyStakes(snap, testHumanId), RolloutStakes.mid);
    });

    test('a caller still in makes it mid, once out it does not count', () {
      final s = _setup();
      s.state.scoreTracker.recordTichuCall(testOpponentLeftId, isGrand: true);
      expect(stakesReasons(_snap(s), testHumanId), {StakesReason.call});
      expect(classifyStakes(_snap(s), testHumanId), RolloutStakes.mid);

      s.state.scoreTracker.recordPlayerFinished(testOpponentLeftId, const []);
      s.state.hands[testOpponentLeftId] = [];
      // The caller is out: no call, but someone is out (high).
      expect(stakesReasons(_snap(s), testHumanId), {StakesReason.someoneOut});
      expect(classifyStakes(_snap(s), testHumanId), RolloutStakes.high);
    });

    test('a trick worth 20 points is mid', () {
      final s = _setup();
      s.state.currentTrickCards.addAll([
        fxCard(CardFace.king, CardColor.red),
        fxCard(CardFace.ten, CardColor.blue),
      ]);
      expect(_snap(s).trickPoints, 20);
      expect(stakesReasons(_snap(s), testHumanId), {StakesReason.richTrick});
      expect(classifyStakes(_snap(s), testHumanId), RolloutStakes.mid);
    });

    test('players close to going out are high', () {
      expect(
        stakesReasons(_snap(_setup(others: const [3, 10, 10])), testHumanId),
        {StakesReason.opponentClose},
      );
      expect(
        stakesReasons(_snap(_setup(others: const [10, 2, 10])), testHumanId),
        {StakesReason.partnerClose},
      );
      expect(
        stakesReasons(_snap(_setup(others: const [10, 10, 4])), testHumanId),
        isEmpty,
      );
      // The same table from the left opponent's seat: seat 0 is an opponent.
      final snap = _snap(_setup(own: 2));
      expect(stakesReasons(snap, testOpponentLeftId), {
        StakesReason.opponentClose,
      });
      expect(classifyStakes(snap, testOpponentLeftId), RolloutStakes.high);
    });

    test('own endgame is high from 5 cards', () {
      expect(stakesReasons(_snap(_setup(own: 5)), testHumanId), {
        StakesReason.endgame,
      });
      expect(
        classifyStakes(_snap(_setup(own: 6)), testHumanId),
        RolloutStakes.low,
      );
      final snap = _snap(_setup(own: 4, lead: true));
      expect(stakesReasons(snap, testHumanId), {
        StakesReason.endgame,
        StakesReason.lead,
      });
      expect(classifyStakes(snap, testHumanId), RolloutStakes.high);
    });
  });

  group('stakes rates', () {
    test('defaults keep the uniform rate on average', () {
      final r = StakesRates.forBase(0.5);
      expect(r.high, closeTo(0.7, 1e-9));
      expect(r.mid, closeTo(0.35, 1e-9));
      expect(r.low, closeTo(0.15, 1e-9));
      expect(StakesRates.forBase(1).high, 1.0);
    });

    test('parse overrides named classes only', () {
      final r = StakesRates.parse(
        'high:1.0,low:0.25',
        StakesRates.forBase(0.5),
      )!;
      expect(r.high, 1.0);
      expect(r.mid, closeTo(0.35, 1e-9));
      expect(r.low, 0.25);
      expect(r.of(RolloutStakes.low), 0.25);
      expect(StakesRates.parse('high:2', r), isNull);
      expect(StakesRates.parse('huge:0.5', r), isNull);
      expect(StakesRates.parse('high', r), isNull);
    });
  });
}
