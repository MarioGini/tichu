import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/heuristic_options.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/agents/turn_scorer.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'smart_ai_test_helpers.dart';

void main() {
  test('parses presets and rule lists', () {
    expect(HeuristicOptions.parse('latest').guardPartnerTichu, isTrue);
    expect(HeuristicOptions.parse('latest').strictTichu, isTrue);
    final legacy = HeuristicOptions.parse('legacy');
    expect(legacy.guardPartnerTichu, isFalse);
    expect(legacy.supportPartnerTichu, isFalse);
    expect(legacy.strictTichu, isFalse);
    expect(legacy.announceBeforeSchupf, isFalse);
    final custom = HeuristicOptions.parse('support,announce');
    expect(custom.supportPartnerTichu, isTrue);
    expect(custom.announceBeforeSchupf, isTrue);
    expect(custom.guardPartnerTichu, isFalse);
    expect(custom.strictTichu, isFalse);
  });

  test('rejects unknown rules', () {
    expect(() => HeuristicOptions.parse('support,bogus'), throwsArgumentError);
  });

  test('classic is the fixed baseline, latest adds the tuned rules', () {
    final classic = HeuristicOptions.parse('classic');
    expect(classic.cheapCombos, isFalse);
    expect(classic.planPass, isTrue);
    expect(classic.weights, isEmpty);
    final latest = HeuristicOptions.parse('latest');
    expect(latest.cheapCombos, isTrue);
    expect(latest.planPass, isFalse);
    expect(latest.weights['controlPreservation'], 6);
  });

  test('switches rules off and overrides scorer weights', () {
    final o = HeuristicOptions.parse(
      'latest,-early_dog,-cheap_combos,conserve,lowLeadPreference:4',
    );
    expect(o.on('early_dog'), isFalse);
    expect(o.on('partner_pass'), isTrue);
    expect(o.cheapCombos, isFalse);
    expect(o.conserveControls, isTrue);
    expect(o.weights['lowLeadPreference'], 4);
    // The latest preset's own overrides are kept.
    expect(o.weights['unbeatableLine'], 2.5);
    expect(const PolicyWeights().withOverrides(o.weights).lowLeadPreference, 4);
    expect(
      () => const PolicyWeights().withOverrides({'bogus': 1}),
      throwsArgumentError,
    );
    expect(() => HeuristicOptions.parse('latest,x:abc'), throwsArgumentError);
  });

  group('cheap_combos', () {
    // Opponent leads 4-4-T-T-T; we hold Q-Q-Q, A-A-A and 6-6.
    Card c(final CardFace f, final CardColor color) => Card(f, color);
    final hand = [
      c(CardFace.two, CardColor.red),
      c(CardFace.six, CardColor.red),
      c(CardFace.six, CardColor.blue),
      c(CardFace.queen, CardColor.red),
      c(CardFace.queen, CardColor.blue),
      c(CardFace.queen, CardColor.green),
      c(CardFace.ace, CardColor.red),
      c(CardFace.ace, CardColor.blue),
      c(CardFace.ace, CardColor.green),
      c(CardFace.nine, CardColor.black),
    ];
    DeckState trick() => DeckState(
      TichuTurn(TurnType.fullHouse, [
        c(CardFace.four, CardColor.red),
        c(CardFace.four, CardColor.blue),
        c(CardFace.ten, CardColor.red),
        c(CardFace.ten, CardColor.blue),
        c(CardFace.ten, CardColor.green),
      ]),
      CardFace.none,
    )..currentWinner = leftId;

    Future<List<CardFace>> played(final HeuristicOptions options) async {
      final action = await SmartAiAgent(
        aiId,
        options: options,
      ).selectTurn(aiSnapshot(myHand: hand, deck: trick()));
      expect(action, isA<PlayTurnAction>());
      return [for (final card in (action as PlayTurnAction).cards) card.face]
        ..sort((final a, final b) => a.index.compareTo(b.index));
    }

    test('latest beats a full house with the cheapest full house', () async {
      expect(await played(HeuristicOptions.latest), [
        CardFace.six,
        CardFace.six,
        CardFace.queen,
        CardFace.queen,
        CardFace.queen,
      ]);
    });

    test('leads the full house with the low pair', () async {
      // Classic leads 4-4-4-J-J here and keeps the nines.
      final leadHand = [
        c(CardFace.three, CardColor.red),
        c(CardFace.four, CardColor.red),
        c(CardFace.four, CardColor.blue),
        c(CardFace.four, CardColor.green),
        c(CardFace.eight, CardColor.red),
        c(CardFace.nine, CardColor.red),
        c(CardFace.nine, CardColor.blue),
        c(CardFace.jack, CardColor.red),
        c(CardFace.jack, CardColor.blue),
        c(CardFace.ace, CardColor.red),
      ];
      Future<List<CardFace>> lead(final HeuristicOptions options) async {
        final action = await SmartAiAgent(
          aiId,
          options: options,
        ).selectTurn(aiSnapshot(myHand: leadHand));
        return [for (final card in (action as PlayTurnAction).cards) card.face]
          ..sort((final a, final b) => a.index.compareTo(b.index));
      }

      expect(await lead(HeuristicOptions.classic), [
        CardFace.four,
        CardFace.four,
        CardFace.four,
        CardFace.jack,
        CardFace.jack,
      ]);
      expect(await lead(HeuristicOptions.latest), [
        CardFace.four,
        CardFace.four,
        CardFace.four,
        CardFace.nine,
        CardFace.nine,
      ]);
    });
  });
}
