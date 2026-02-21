import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

const aiTestSelfId = 'ai-0';
const aiTestLeftId = 'ai-1';
const aiTestPartnerId = 'ai-2';
const aiTestRightId = 'ai-3';

final aiTestPlayers = <GamePlayer>[
  const GamePlayer(
    id: aiTestSelfId,
    name: 'AI-0',
    seat: 0,
    type: PlayerType.automated,
  ),
  const GamePlayer(
    id: aiTestLeftId,
    name: 'AI-1',
    seat: 1,
    type: PlayerType.automated,
  ),
  const GamePlayer(
    id: aiTestPartnerId,
    name: 'AI-2',
    seat: 2,
    type: PlayerType.automated,
  ),
  const GamePlayer(
    id: aiTestRightId,
    name: 'AI-3',
    seat: 3,
    type: PlayerType.automated,
  ),
];

DeckState aiEmptyDeck() =>
    DeckState(TichuTurn(TurnType.empty, const []), CardFace.none);

List<Card> aiDefaultHand() => [
  Card(CardFace.two, CardColor.red),
  Card(CardFace.five, CardColor.blue),
  Card(CardFace.eight, CardColor.green),
  Card(CardFace.jack, CardColor.black),
  Card(CardFace.king, CardColor.red),
];

GameSnapshot aiSnapshot({
  required final List<Card> myHand,
  final DeckState? deck,
  final Map<String, List<Card>>? otherHands,
  final Map<String, TichuCall>? tichuCalls,
  final Map<String, bool>? canCallTichuByPlayer,
  final String? currentPlayerId,
  final String? lastPlayedBy,
  final TichuTurn? lastPlayedTurn,
  final Map<String, List<SchupfReceipt>>? schupfReceipts,
  final int roundNumber = 1,
}) {
  final hands = <String, List<Card>>{
    aiTestSelfId: myHand,
    aiTestLeftId: otherHands?[aiTestLeftId] ?? aiDefaultHand(),
    aiTestPartnerId: otherHands?[aiTestPartnerId] ?? aiDefaultHand(),
    aiTestRightId: otherHands?[aiTestRightId] ?? aiDefaultHand(),
  };

  final scoreState = ScoreState.initial().copyWith(
    tichuCalls: tichuCalls ?? const {},
    roundNumber: roundNumber,
  );

  return GameSnapshot(
    gameId: 'ai-test-game',
    players: aiTestPlayers,
    hands: hands,
    deck: deck ?? aiEmptyDeck(),
    trickPoints: 0,
    activeWish: deck?.wish ?? CardFace.none,
    currentPlayerId: currentPlayerId ?? aiTestSelfId,
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
    canCallTichuByPlayer: canCallTichuByPlayer ?? const {},
    grandTichuDecisions: const {},
    schupfCompletedPlayers: const [],
    schupfReceipts: schupfReceipts ?? const {},
  );
}
