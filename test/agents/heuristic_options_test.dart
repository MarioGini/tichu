import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/heuristic_options.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/agents/turn_scorer.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'smart_ai_test_helpers.dart';

void main() {
  test('parses rule switches and scorer weights', () {
    expect(HeuristicOptions.parse('latest').off, HeuristicOptions.defaultOff);
    expect(HeuristicOptions.parse('latest').on('interrupt_bomb'), isFalse);
    expect(
      HeuristicOptions.parse('interrupt_bomb').on('interrupt_bomb'),
      isTrue,
    );
    expect(HeuristicOptions.parse('latest').weights, isEmpty);
    final o = HeuristicOptions.parse(
      'latest,-early_dog,-cheap_combos,cheap_combos,lowLeadPreference:4',
    );
    expect(o.on('early_dog'), isFalse);
    expect(o.on('partner_pass'), isTrue);
    expect(o.on('cheap_combos'), isTrue);
    expect(o.weights, {'lowLeadPreference': 4.0});
    expect(const PolicyWeights().withOverrides(o.weights).lowLeadPreference, 4);
  });

  test('rejects unknown rules and weights', () {
    expect(() => HeuristicOptions.parse('-bogus'), throwsArgumentError);
    expect(() => HeuristicOptions.parse('classic'), throwsArgumentError);
    expect(() => HeuristicOptions.parse('latest,x:abc'), throwsArgumentError);
    expect(
      () => const PolicyWeights().withOverrides({'bogus': 1}),
      throwsArgumentError,
    );
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
      // Without the rule the scorer leads 4-4-4-J-J and keeps the nines.
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

      expect(await lead(HeuristicOptions.parse('-cheap_combos')), [
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
