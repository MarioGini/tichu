import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/play_tactics_policy.dart';
import 'package:tichu/agents/schupf_strategy.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/agents/table_relationships.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/find_turn.dart';
import 'package:tichu/game/turn/tichu_data.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _aiId = 'ai-0';
const _partnerId = 'ai-2';
const _leftId = 'ai-1';
const _rightId = 'ai-3';

final _players = [
  const GamePlayer(
    id: _aiId,
    name: 'AI-0',
    seat: 0,
    type: PlayerType.automated,
  ),
  const GamePlayer(
    id: _leftId,
    name: 'AI-1',
    seat: 1,
    type: PlayerType.automated,
  ),
  const GamePlayer(
    id: _partnerId,
    name: 'AI-2',
    seat: 2,
    type: PlayerType.automated,
  ),
  const GamePlayer(
    id: _rightId,
    name: 'AI-3',
    seat: 3,
    type: PlayerType.automated,
  ),
];

GameSnapshot _snapshot({
  required final List<Card> myHand,
  final DeckState? deck,
  final Map<String, List<Card>>? otherHands,
  final Map<String, TichuCall>? tichuCalls,
  final String? lastPlayedBy,
  final TichuTurn? lastPlayedTurn,
  final CardFace? activeWish,
}) {
  final hands = <String, List<Card>>{
    _aiId: myHand,
    _leftId: otherHands?[_leftId] ?? _defaultHand(),
    _partnerId: otherHands?[_partnerId] ?? _defaultHand(),
    _rightId: otherHands?[_rightId] ?? _defaultHand(),
  };
  final scoreState = ScoreState.initial().copyWith(
    tichuCalls: tichuCalls ?? const {},
  );
  return GameSnapshot(
    gameId: 'test-game',
    players: _players,
    hands: hands,
    deck: deck ?? _emptyDeck(),
    trickPoints: 0,
    activeWish: activeWish ?? deck?.wish ?? CardFace.none,
    currentPlayerId: _aiId,
    consecutivePasses: 0,
    lastPlayedBy: lastPlayedBy,
    lastPlayedTurn: lastPlayedTurn,
    lastDragonGiveBy: null,
    lastDragonGiveTo: null,
    pendingDragonGiveBy: null,
    pendingDragonGiveTargets: const [],
    pendingOpponentPlayerId: null,
    pendingOpponentCards: const [],
    pendingOpponentPass: false,
    scoreState: scoreState,
    opponentAwaitingConfirmation: false,
    phase: GamePhase.play,
    grandTichuDecisions: const {},
    schupfCompletedPlayers: const [],
    schupfReceipts: const {},
  );
}

DeckState _emptyDeck() =>
    DeckState(TichuTurn(TurnType.empty, const []), CardFace.none);

List<Card> _defaultHand() => [
  Card(CardFace.two, CardColor.red),
  Card(CardFace.five, CardColor.blue),
  Card(CardFace.eight, CardColor.green),
  Card(CardFace.jack, CardColor.black),
  Card(CardFace.king, CardColor.red),
];

class _FixedSchupfStrategy implements SchupfStrategy {
  const _FixedSchupfStrategy({
    required this.toLeft,
    required this.toPartner,
    required this.toRight,
  });

  final Card toLeft;
  final Card toPartner;
  final Card toRight;

  @override
  Future<SchupfAction> selectSchupfCards(
    final GameSnapshot snapshot,
    final String playerId,
  ) async => SchupfAction(
    playerId: playerId,
    toLeft: toLeft,
    toPartner: toPartner,
    toRight: toRight,
  );
}

class _ForceEmptyValidPlaysPolicy extends PlayTacticsPolicy {
  const _ForceEmptyValidPlaysPolicy();

  @override
  PassAction? selectPartnerSupportPass({
    required final String playerId,
    required final GameSnapshot snapshot,
    required final DeckState deck,
    required final List<Card> hand,
    required final TableRelationships table,
  }) => null;

  @override
  TichuTurn? selectPartnerFinishLead({
    required final GameSnapshot snapshot,
    required final List<TichuTurn> legalTurns,
    required final bool isLeading,
    required final TableRelationships table,
  }) => null;

  @override
  TichuTurn? selectMahjongLeadTurn({
    required final List<TichuTurn> legalTurns,
    required final DeckState deck,
    required final List<Card> hand,
    required final bool isLeading,
    required final TichuTurn Function(List<TichuTurn>) selectPlay,
  }) => null;

  @override
  List<TichuTurn> wishPreferredTurns({
    required final List<TichuTurn> legalTurns,
    required final DeckState deck,
  }) => const <TichuTurn>[];

  @override
  List<TichuTurn> filterWishValidPlays({
    required final DeckState deck,
    required final List<TichuTurn> legalTurns,
    required final List<Card> hand,
  }) => const <TichuTurn>[];
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late SmartAiAgent agent;

  setUp(() {
    agent = SmartAiAgent(_aiId);
  });

  // -----------------------------------------------------------------------
  // Grand Tichu / Tichu
  // -----------------------------------------------------------------------

  group('shouldCallGrandTichu', () {
    test('always returns false', () async {
      final snapshot = _snapshot(
        myHand: [
          Card(CardFace.dragon, CardColor.special),
          Card(CardFace.phoenix, CardColor.special),
          Card(CardFace.ace, CardColor.red),
          Card(CardFace.ace, CardColor.blue),
          Card(CardFace.ace, CardColor.green),
          Card(CardFace.ace, CardColor.black),
          Card(CardFace.king, CardColor.red),
          Card(CardFace.king, CardColor.blue),
        ],
      );
      expect(await agent.shouldCallGrandTichu(snapshot), false);
    });
  });

  group('shouldCallTichu', () {
    test('declines with average cards', () async {
      final snapshot = _snapshot(
        myHand: [
          Card(CardFace.two, CardColor.red),
          Card(CardFace.three, CardColor.blue),
          Card(CardFace.four, CardColor.green),
          Card(CardFace.five, CardColor.black),
          Card(CardFace.six, CardColor.red),
          Card(CardFace.seven, CardColor.blue),
          Card(CardFace.eight, CardColor.green),
          Card(CardFace.nine, CardColor.black),
          Card(CardFace.ten, CardColor.red),
          Card(CardFace.jack, CardColor.blue),
          Card(CardFace.queen, CardColor.green),
          Card(CardFace.king, CardColor.black),
          Card(CardFace.dog, CardColor.special),
          Card(CardFace.mahJong, CardColor.special),
        ],
      );
      expect(await agent.shouldCallTichu(snapshot), false);
    });
  });

  // -----------------------------------------------------------------------
  // Schupfen
  // -----------------------------------------------------------------------

  group('selectSchupfCards', () {
    test('returns three different cards', () async {
      final hand = [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.eight, CardColor.green),
        Card(CardFace.jack, CardColor.black),
        Card(CardFace.king, CardColor.red),
        Card(CardFace.ace, CardColor.blue),
      ];
      final snapshot = _snapshot(myHand: hand);
      final action = await agent.selectSchupfCards(snapshot);

      // All three must be cards from the hand.
      expect(hand.contains(action.toLeft), true);
      expect(hand.contains(action.toPartner), true);
      expect(hand.contains(action.toRight), true);
    });

    test('avoids schupfing special cards', () async {
      final hand = [
        Card(CardFace.dragon, CardColor.special),
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.dog, CardColor.special),
        Card(CardFace.mahJong, CardColor.special),
        Card(CardFace.two, CardColor.red),
        Card(CardFace.three, CardColor.blue),
        Card(CardFace.four, CardColor.green),
        Card(CardFace.five, CardColor.black),
      ];
      final snapshot = _snapshot(myHand: hand);
      final action = await agent.selectSchupfCards(snapshot);

      final specials = [
        CardFace.dragon,
        CardFace.phoenix,
        CardFace.dog,
        CardFace.mahJong,
      ];
      expect(specials.contains(action.toLeft.face), false);
      expect(specials.contains(action.toRight.face), false);
      // Partner may get a higher card but still not a special.
      expect(specials.contains(action.toPartner.face), false);
    });

    test('gives low cards to opponents', () async {
      final hand = [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.three, CardColor.blue),
        Card(CardFace.queen, CardColor.green),
        Card(CardFace.king, CardColor.black),
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.ace, CardColor.blue),
      ];
      final snapshot = _snapshot(myHand: hand);
      final action = await agent.selectSchupfCards(snapshot);

      // Opponents should get the lowest cards.
      expect(action.toLeft.value, lessThanOrEqualTo(3));
      expect(action.toRight.value, lessThanOrEqualTo(3));
    });

    test('throws with fewer than 3 cards', () async {
      final hand = [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.three, CardColor.blue),
      ];
      final snapshot = _snapshot(myHand: hand);
      expect(
        () => agent.selectSchupfCards(snapshot),
        throwsA(isA<StateError>()),
      );
    });

    test('gives best card to partner on grand tichu', () async {
      final hand = [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.ten, CardColor.blue),
        Card(CardFace.king, CardColor.green),
        Card(CardFace.ace, CardColor.black),
      ];
      final snapshot = _snapshot(
        myHand: hand,
        tichuCalls: {_partnerId: TichuCall.grandTichu},
      );

      final action = await agent.selectSchupfCards(snapshot);
      expect(action.toPartner.face, CardFace.ace);
    });

    test('gives dog to opponent who called grand tichu', () async {
      final hand = [
        Card(CardFace.dog, CardColor.special),
        Card(CardFace.two, CardColor.red),
        Card(CardFace.three, CardColor.blue),
        Card(CardFace.four, CardColor.green),
      ];
      final snapshot = _snapshot(
        myHand: hand,
        tichuCalls: {_leftId: TichuCall.grandTichu},
      );

      final action = await agent.selectSchupfCards(snapshot);
      expect(action.toLeft.face, CardFace.dog);
    });

    test('prefers even-valued card to the right opponent', () async {
      final hand = [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.three, CardColor.blue),
        Card(CardFace.four, CardColor.green),
        Card(CardFace.five, CardColor.black),
      ];
      final snapshot = _snapshot(myHand: hand);

      final action = await agent.selectSchupfCards(snapshot);
      expect(action.toRight.value.toInt().isEven, true);
    });
  });

  // -----------------------------------------------------------------------
  // Play selection
  // -----------------------------------------------------------------------

  group('selectTurn', () {
    test('passes when hand is empty', () async {
      final snapshot = _snapshot(myHand: []);
      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PassAction>());
    });

    test('plays a legal single card on empty deck', () async {
      final hand = [
        Card(CardFace.five, CardColor.red),
        Card(CardFace.ten, CardColor.blue),
      ];
      final snapshot = _snapshot(myHand: hand, deck: _emptyDeck());
      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      // Must be a card from the hand.
      for (final c in play.cards) {
        expect(
          hand.any((final h) => h.face == c.face),
          true,
          reason: 'played card ${c.face} should be from hand',
        );
      }
    });

    test('follows with a higher single when required', () async {
      final hand = [
        Card(CardFace.three, CardColor.red),
        Card(CardFace.eight, CardColor.blue),
        Card(CardFace.king, CardColor.green),
      ];
      final deckTurn = TichuTurn(TurnType.single, [
        Card(CardFace.five, CardColor.black),
      ]);
      final deck = DeckState(deckTurn, CardFace.none);
      deck.currentWinner = _leftId;
      final snapshot = _snapshot(myHand: hand, deck: deck);

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      expect(play.cards.length, 1);
      // The played card must beat the 5 on the deck.
      expect(play.cards.first.value, greaterThan(5));
    });

    test('passes when it cannot beat the deck', () async {
      final hand = [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.three, CardColor.blue),
      ];
      final deckTurn = TichuTurn(TurnType.single, [
        Card(CardFace.ace, CardColor.black),
      ]);
      final deck = DeckState(deckTurn, CardFace.none);
      deck.currentWinner = _leftId;
      final snapshot = _snapshot(myHand: hand, deck: deck);

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PassAction>());
    });

    test('does not play phoenix as single on low card', () async {
      final hand = [
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.seven, CardColor.red),
      ];
      final deckTurn = TichuTurn(TurnType.single, [
        Card(CardFace.six, CardColor.black),
      ]);
      final deck = DeckState(deckTurn, CardFace.none);
      deck.currentWinner = _leftId;
      final snapshot = _snapshot(myHand: hand, deck: deck);

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      expect(play.cards.length, 1);
      expect(play.cards.first.face, CardFace.seven);
    });

    test('can play phoenix as single on king or higher', () async {
      final hand = [
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.ace, CardColor.red),
      ];
      final deckTurn = TichuTurn(TurnType.single, [
        Card(CardFace.king, CardColor.black),
      ]);
      final deck = DeckState(deckTurn, CardFace.none);
      deck.currentWinner = _leftId;
      final snapshot = _snapshot(myHand: hand, deck: deck);

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      expect(play.cards.length, 1);
      expect(play.cards.first.face, CardFace.phoenix);
    });

    test('passes when tactics policy filters all valid plays', () async {
      final customAgent = SmartAiAgent(
        _aiId,
        playTacticsPolicy: const _ForceEmptyValidPlaysPolicy(),
      );
      final hand = [
        Card(CardFace.five, CardColor.red),
        Card(CardFace.king, CardColor.blue),
      ];

      final action = await customAgent.selectTurn(
        _snapshot(myHand: hand, deck: _emptyDeck()),
      );

      expect(action, isA<PassAction>());
    });

    test('prefers non-bomb plays', () async {
      final hand = [
        Card(CardFace.five, CardColor.red),
        Card(CardFace.five, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.ten, CardColor.red),
      ];
      final deckTurn = TichuTurn(TurnType.single, [
        Card(CardFace.three, CardColor.black),
      ]);
      final deck = DeckState(deckTurn, CardFace.none);
      deck.currentWinner = _leftId;
      final snapshot = _snapshot(myHand: hand, deck: deck);

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      // Should play the ten as a single instead of bombing with four 5s.
      expect(play.cards.length, 1);
    });

    test('plays all remaining cards to go out', () async {
      // Only one card left → must play it.
      final hand = [Card(CardFace.king, CardColor.red)];
      final snapshot = _snapshot(myHand: hand, deck: _emptyDeck());
      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      expect(play.cards.length, 1);
      expect(play.cards.first.face, CardFace.king);
    });

    test('plays phoenix pair to finish when legal', () async {
      final hand = [
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.king, CardColor.red),
      ];
      final snapshot = _snapshot(myHand: hand, deck: _emptyDeck());

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      expect(play.cards.length, 2);
      expect(getTurn(play.cards).type, TurnType.pair);
    });

    test('finishes instead of passing for partner support', () async {
      final hand = [
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.king, CardColor.red),
      ];
      final deckTurn = TichuTurn(TurnType.pair, [
        Card(CardFace.queen, CardColor.black),
        Card(CardFace.queen, CardColor.red),
      ]);
      final deck = DeckState(deckTurn, CardFace.none);
      deck.currentWinner = _partnerId;

      final snapshot = _snapshot(
        myHand: hand,
        deck: deck,
        tichuCalls: {_partnerId: TichuCall.tichu},
        lastPlayedBy: _partnerId,
        lastPlayedTurn: deckTurn,
      );

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      expect(play.cards.length, 2);
      expect(getTurn(play.cards).type, TurnType.pair);
    });

    test('avoids burning high cards early when leading', () async {
      final hand = [
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.king, CardColor.blue),
        Card(CardFace.queen, CardColor.green),
        Card(CardFace.jack, CardColor.black),
        Card(CardFace.three, CardColor.red),
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.six, CardColor.black),
        Card(CardFace.seven, CardColor.red),
      ];
      final snapshot = _snapshot(myHand: hand, deck: _emptyDeck());

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;

      final playedFaces = play.cards.map((final c) => c.face).toSet();
      expect(playedFaces.contains(CardFace.ace), false);
      expect(playedFaces.contains(CardFace.king), false);
    });

    test('prefers multi-card lines when opponent is low', () async {
      final hand = [
        Card(CardFace.three, CardColor.red),
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.six, CardColor.black),
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.king, CardColor.blue),
      ];
      final snapshot = _snapshot(
        myHand: hand,
        deck: _emptyDeck(),
        otherHands: {
          _leftId: List.generate(
            4,
            (final i) => Card(CardFace.two, CardColor.red),
          ),
          _partnerId: _defaultHand(),
          _rightId: List.generate(
            6,
            (final i) => Card(CardFace.three, CardColor.blue),
          ),
        },
      );

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      expect(getTurn(play.cards).type, TurnType.straight);
    });

    test('avoids singles when opponent has 1 card', () async {
      final hand = [
        Card(CardFace.three, CardColor.red),
        Card(CardFace.four, CardColor.blue),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.six, CardColor.black),
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.king, CardColor.blue),
      ];
      final snapshot = _snapshot(
        myHand: hand,
        deck: _emptyDeck(),
        otherHands: {
          _leftId: [Card(CardFace.two, CardColor.red)],
          _partnerId: _defaultHand(),
          _rightId: List.generate(
            6,
            (final i) => Card(CardFace.three, CardColor.blue),
          ),
        },
      );

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      expect(getTurn(play.cards).type, TurnType.straight);
    });

    test('passes to support partner tichu when partner is winning', () async {
      final hand = [
        Card(CardFace.nine, CardColor.red),
        Card(CardFace.jack, CardColor.blue),
      ];
      final deckTurn = TichuTurn(TurnType.single, [
        Card(CardFace.king, CardColor.black),
      ]);
      final deck = DeckState(deckTurn, CardFace.none);

      final snapshot = _snapshot(
        myHand: hand,
        deck: deck,
        otherHands: {
          _leftId: _defaultHand(),
          _partnerId: [
            Card(CardFace.two, CardColor.red),
            Card(CardFace.three, CardColor.blue),
            Card(CardFace.four, CardColor.green),
            Card(CardFace.five, CardColor.red),
          ],
          _rightId: _defaultHand(),
        },
        tichuCalls: {_partnerId: TichuCall.tichu},
        lastPlayedBy: _partnerId,
        lastPlayedTurn: deckTurn,
      );

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PassAction>());
    });

    test(
      'plays normally when opponent is leading despite partner tichu call',
      () async {
        final hand = [Card(CardFace.six, CardColor.red)];
        final deckTurn = TichuTurn(TurnType.single, [
          Card(CardFace.five, CardColor.black),
        ]);
        final deck = DeckState(deckTurn, CardFace.none);
        deck.currentWinner = _leftId;

        final snapshot = _snapshot(
          myHand: hand,
          deck: deck,
          otherHands: {
            _leftId: _defaultHand(),
            _partnerId: [Card(CardFace.ace, CardColor.red)],
            _rightId: _defaultHand(),
          },
          tichuCalls: {_partnerId: TichuCall.tichu},
          lastPlayedBy: _leftId,
          lastPlayedTurn: deckTurn,
        );

        final action = await agent.selectTurn(snapshot);
        expect(action, isA<PlayTurnAction>());
      },
    );

    test(
      'plays normally when partner is winning high trick without tichu call',
      () async {
        final hand = [
          Card(CardFace.ace, CardColor.red),
          Card(CardFace.ten, CardColor.blue),
        ];
        final deckTurn = TichuTurn(TurnType.single, [
          Card(CardFace.king, CardColor.black),
        ]);
        final deck = DeckState(deckTurn, CardFace.none);
        deck.currentWinner = _partnerId;

        final snapshot = _snapshot(
          myHand: hand,
          deck: deck,
          otherHands: {
            _leftId: _defaultHand(),
            _partnerId: [
              Card(CardFace.three, CardColor.red),
              Card(CardFace.four, CardColor.blue),
              Card(CardFace.five, CardColor.green),
            ],
            _rightId: _defaultHand(),
          },
          lastPlayedBy: _partnerId,
          lastPlayedTurn: deckTurn,
        );

        final action = await agent.selectTurn(snapshot);
        expect(action, isA<PlayTurnAction>());
      },
    );

    test(
      'plays a stronger interrupt when opponent tichu is near finish',
      () async {
        final hand = [
          Card(CardFace.two, CardColor.green),
          Card(CardFace.six, CardColor.red),
          Card(CardFace.king, CardColor.blue),
        ];
        final deckTurn = TichuTurn(TurnType.single, [
          Card(CardFace.five, CardColor.black),
        ]);
        final deck = DeckState(deckTurn, CardFace.none);
        deck.currentWinner = _leftId;

        final snapshot = _snapshot(
          myHand: hand,
          deck: deck,
          otherHands: {
            _leftId: [
              Card(CardFace.ace, CardColor.red),
              Card(CardFace.queen, CardColor.green),
            ],
            _partnerId: _defaultHand(),
            _rightId: _defaultHand(),
          },
          tichuCalls: {_leftId: TichuCall.tichu},
          lastPlayedBy: _leftId,
          lastPlayedTurn: deckTurn,
        );

        final action = await agent.selectTurn(snapshot);
        expect(action, isA<PlayTurnAction>());
        final play = action as PlayTurnAction;
        expect(play.cards.length, 1);
        expect(play.cards.first.face, CardFace.king);
      },
    );

    test('leads a single to help partner finish tichu', () async {
      final hand = [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.ten, CardColor.blue),
      ];

      final snapshot = _snapshot(
        myHand: hand,
        deck: _emptyDeck(),
        otherHands: {
          _leftId: _defaultHand(),
          _partnerId: [Card(CardFace.ace, CardColor.red)],
          _rightId: _defaultHand(),
        },
        tichuCalls: {_partnerId: TichuCall.tichu},
      );

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      expect(getTurn(play.cards).type, TurnType.single);
      expect(play.cards.first.face, CardFace.two);
    });

    test('plays dog early when leading', () async {
      final hand = [
        Card(CardFace.dog, CardColor.special),
        Card(CardFace.five, CardColor.blue),
      ];

      final snapshot = _snapshot(myHand: hand, deck: _emptyDeck());

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      expect(getTurn(play.cards).type, TurnType.dog);
    });

    test(
      'leads mahjong instead of dog on game opening when both are in hand',
      () async {
        final hand = [
          Card(CardFace.dog, CardColor.special),
          Card(CardFace.mahJong, CardColor.special),
          Card(CardFace.king, CardColor.blue),
        ];

        final snapshot = _snapshot(myHand: hand, deck: _emptyDeck());

        final action = await agent.selectTurn(snapshot);
        expect(action, isA<PlayTurnAction>());
        final play = action as PlayTurnAction;
        expect(play.cards.any((final c) => c.face == CardFace.mahJong), isTrue);
        expect(getTurn(play.cards).type, isNot(TurnType.dog));
      },
    );

    test(
      'prefers mahjong straight lead over dog on game opening when available',
      () async {
        final hand = [
          Card(CardFace.dog, CardColor.special),
          Card(CardFace.mahJong, CardColor.special),
          Card(CardFace.two, CardColor.red),
          Card(CardFace.three, CardColor.blue),
          Card(CardFace.four, CardColor.green),
          Card(CardFace.five, CardColor.black),
        ];

        final snapshot = _snapshot(myHand: hand, deck: _emptyDeck());

        final action = await agent.selectTurn(snapshot);
        expect(action, isA<PlayTurnAction>());
        final play = action as PlayTurnAction;
        expect(play.cards.any((final c) => c.face == CardFace.mahJong), isTrue);
        expect(getTurn(play.cards).type, TurnType.straight);
      },
    );

    test('skips mahjong opening rule after first card of game', () async {
      final hand = [
        Card(CardFace.dog, CardColor.special),
        Card(CardFace.mahJong, CardColor.special),
        Card(CardFace.king, CardColor.blue),
      ];
      final priorTurn = TichuTurn(TurnType.single, [
        Card(CardFace.five, CardColor.black),
      ]);

      final snapshot = _snapshot(
        myHand: hand,
        deck: _emptyDeck(),
        lastPlayedBy: _leftId,
        lastPlayedTurn: priorTurn,
      );

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      expect(getTurn(play.cards).type, TurnType.dog);
    });

    test(
      'responds to single with lowest singleton and preserves pair',
      () async {
        final hand = [
          Card(CardFace.five, CardColor.red),
          Card(CardFace.eight, CardColor.red),
          Card(CardFace.eight, CardColor.blue),
          Card(CardFace.king, CardColor.green),
        ];
        final deckTurn = TichuTurn(TurnType.single, [
          Card(CardFace.three, CardColor.black),
        ]);
        final deck = DeckState(deckTurn, CardFace.none);
        deck.currentWinner = _leftId;
        final snapshot = _snapshot(myHand: hand, deck: deck);

        final action = await agent.selectTurn(snapshot);
        expect(action, isA<PlayTurnAction>());
        final play = action as PlayTurnAction;
        expect(getTurn(play.cards).type, TurnType.single);
        expect(play.cards.first.face, CardFace.five);
      },
    );
  });

  // -----------------------------------------------------------------------
  // Wish handling
  // -----------------------------------------------------------------------

  group('wish enforcement', () {
    test('plays a card fulfilling the wish when possible', () async {
      final hand = [
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.ten, CardColor.blue),
        Card(CardFace.king, CardColor.green),
      ];
      final deckTurn = TichuTurn(TurnType.single, [
        Card(CardFace.five, CardColor.black),
      ]);
      // Active wish for a seven.
      final deck = DeckState(deckTurn, CardFace.seven);
      deck.currentWinner = _leftId;
      final snapshot = _snapshot(myHand: hand, deck: deck);

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      expect(play.cards.any((final c) => c.face == CardFace.seven), true);
    });

    test(
      'does not pass for partner support when wish is fulfillable',
      () async {
        final hand = [
          Card(CardFace.seven, CardColor.red),
          Card(CardFace.king, CardColor.blue),
        ];
        final deckTurn = TichuTurn(TurnType.single, [
          Card(CardFace.five, CardColor.black),
        ]);
        final deck = DeckState(deckTurn, CardFace.seven)
          ..currentWinner = _partnerId;

        final snapshot = _snapshot(
          myHand: hand,
          deck: deck,
          otherHands: {
            _leftId: _defaultHand(),
            _partnerId: [
              Card(CardFace.two, CardColor.red),
              Card(CardFace.three, CardColor.blue),
            ],
            _rightId: _defaultHand(),
          },
          tichuCalls: {_partnerId: TichuCall.tichu},
          lastPlayedBy: _partnerId,
          lastPlayedTurn: deckTurn,
        );

        final action = await agent.selectTurn(snapshot);
        expect(action, isA<PlayTurnAction>());
        final play = action as PlayTurnAction;
        expect(play.cards.any((final c) => c.face == CardFace.seven), isTrue);
      },
    );
  });

  // -----------------------------------------------------------------------
  // Wish selection (when playing Mah Jong)
  // -----------------------------------------------------------------------

  group('wish selection', () {
    test('prefers the card schupfed to the next player', () async {
      final forcedWish = Card(CardFace.seven, CardColor.red);
      final schupfAgent = SmartAiAgent(
        _aiId,
        schupfStrategy: _FixedSchupfStrategy(
          toLeft: forcedWish,
          toPartner: Card(CardFace.three, CardColor.green),
          toRight: Card(CardFace.two, CardColor.black),
        ),
      );

      final schupfSnapshot = _snapshot(
        myHand: [
          forcedWish,
          Card(CardFace.mahJong, CardColor.special),
          Card(CardFace.ace, CardColor.blue),
          Card(CardFace.king, CardColor.green),
        ],
      );
      await schupfAgent.selectSchupfCards(schupfSnapshot);

      final playSnapshot = _snapshot(
        myHand: [
          Card(CardFace.mahJong, CardColor.special),
          Card(CardFace.seven, CardColor.blue),
          Card(CardFace.ace, CardColor.blue),
        ],
        deck: _emptyDeck(),
      );

      final action = await schupfAgent.selectTurn(playSnapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      if (play.cards.any((final c) => c.face == CardFace.mahJong)) {
        expect(play.inputWish, CardFace.seven);
      }
    });

    test('wishes for a high card not in hand', () async {
      final hand = [
        Card(CardFace.mahJong, CardColor.special),
        Card(CardFace.two, CardColor.red),
        Card(CardFace.five, CardColor.blue),
      ];
      final snapshot = _snapshot(myHand: hand, deck: _emptyDeck());

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      // The agent should wish for a high card it doesn't hold.
      if (play.cards.any((final c) => c.face == CardFace.mahJong)) {
        expect(
          play.inputWish,
          isIn([
            CardFace.ace,
            CardFace.king,
            CardFace.queen,
            CardFace.jack,
            CardFace.ten,
          ]),
        );
      }
    });

    test('returns no wish when holding all high cards', () async {
      final hand = [
        Card(CardFace.mahJong, CardColor.special),
        Card(CardFace.ace, CardColor.red),
        Card(CardFace.king, CardColor.blue),
        Card(CardFace.queen, CardColor.green),
        Card(CardFace.jack, CardColor.black),
        Card(CardFace.ten, CardColor.red),
      ];
      final snapshot = _snapshot(myHand: hand, deck: _emptyDeck());

      final action = await agent.selectTurn(snapshot);
      expect(action, isA<PlayTurnAction>());
      final play = action as PlayTurnAction;
      if (play.cards.any((final c) => c.face == CardFace.mahJong)) {
        expect(play.inputWish, CardFace.none);
      }
    });
  });

  // -----------------------------------------------------------------------
  // Dragon give logic
  // -----------------------------------------------------------------------

  group('selectDragonGive', () {
    test('avoids opponent who declared tichu', () {
      final agent = SmartAiAgent(_aiId);

      final snapshot = _snapshot(
        myHand: [Card(CardFace.dragon, CardColor.special)],
        otherHands: {
          _leftId: List.generate(
            6,
            (final i) => Card(CardFace.two, CardColor.red),
          ),
          _partnerId: _defaultHand(),
          _rightId: List.generate(
            2,
            (final i) => Card(CardFace.two, CardColor.blue),
          ),
        },
        tichuCalls: {_leftId: TichuCall.tichu},
      );

      final seat = agent.selectDragonGive(snapshot);
      // Left declared Tichu → give to right opponent.
      expect(seat, 3);
    });

    test('gives to opponent with more cards', () {
      final agent = SmartAiAgent(_aiId);

      // Left has 8 cards, right has 3 cards.
      final snapshot = _snapshot(
        myHand: [Card(CardFace.dragon, CardColor.special)],
        otherHands: {
          _leftId: List.generate(
            8,
            (final i) => Card(CardFace.two, CardColor.red),
          ),
          _partnerId: _defaultHand(),
          _rightId: List.generate(
            3,
            (final i) => Card(CardFace.two, CardColor.blue),
          ),
        },
      );

      final seat = agent.selectDragonGive(snapshot);
      // Left opponent (seat 1) has more cards → should give to seat 1.
      expect(seat, 1);
    });

    test('gives to right opponent when right has more cards', () {
      final agent = SmartAiAgent(_aiId);

      final snapshot = _snapshot(
        myHand: [Card(CardFace.dragon, CardColor.special)],
        otherHands: {
          _leftId: List.generate(
            2,
            (final i) => Card(CardFace.two, CardColor.red),
          ),
          _partnerId: _defaultHand(),
          _rightId: List.generate(
            10,
            (final i) => Card(CardFace.two, CardColor.blue),
          ),
        },
      );

      final seat = agent.selectDragonGive(snapshot);
      // Right opponent (seat 3) has more cards → should give to seat 3.
      expect(seat, 3);
    });
  });

  // -----------------------------------------------------------------------
  // Phoenix value
  // -----------------------------------------------------------------------

  group('selectPhoenixValue', () {
    test('returns 0 when no phoenix in cards', () {
      final agent = SmartAiAgent(_aiId);
      final cards = [Card(CardFace.five, CardColor.red)];
      expect(agent.selectPhoenixValue(_emptyDeck(), cards), 0);
    });

    test('returns phoenix value from the card itself', () {
      final agent = SmartAiAgent(_aiId);
      final cards = [const Card.phoenix(7.5)];
      expect(agent.selectPhoenixValue(_emptyDeck(), cards), 7.5);
    });
  });
}
