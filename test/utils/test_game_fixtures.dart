import 'package:tichu/services/game_backend.dart';
import 'package:tichu/view_model/scoring/score_tracker.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';

const testHumanId = 'player-0';
const testAiLeftId = 'player-1';
const testAiPartnerId = 'player-2';
const testAiRightId = 'player-3';

final testPlayers = [
  const GamePlayer(
    id: testHumanId,
    name: 'You',
    seat: 0,
    type: PlayerType.human,
  ),
  const GamePlayer(
    id: testAiLeftId,
    name: 'AI 1',
    seat: 1,
    type: PlayerType.ai,
  ),
  const GamePlayer(
    id: testAiPartnerId,
    name: 'AI 2 (Partner)',
    seat: 2,
    type: PlayerType.ai,
  ),
  const GamePlayer(
    id: testAiRightId,
    name: 'AI 3',
    seat: 3,
    type: PlayerType.ai,
  ),
];

PlayerSnapshot buildPlayerSnapshot({
  List<Card>? hand,
  DeckState? deck,
  String? currentPlayerId,
  String? pendingAiPlayerId,
  List<Card>? pendingAiCards,
  bool pendingAiPass = false,
  bool aiAwaitingConfirmation = false,
  Map<String, int>? opponentCardCounts,
  CardFace activeWish = CardFace.none,
  int trickPoints = 0,
  int consecutivePasses = 0,
  String? lastPlayedBy,
  TichuTurn? lastPlayedTurn,
  String? lastDragonGiveBy,
  String? lastDragonGiveTo,
  String? pendingDragonGiveBy,
  List<String>? pendingDragonGiveTargets,
  ScoreState? scoreState,
  List<SchupfReceipt>? schupfReceipts,
}) {
  return PlayerSnapshot(
    gameId: 'test-game',
    players: testPlayers,
    hand:
        hand ??
        [
          Card(CardFace.two, CardColor.red),
          Card(CardFace.three, CardColor.blue),
          Card(CardFace.four, CardColor.green),
        ],
    opponentCardCounts:
        opponentCardCounts ??
        const {testAiLeftId: 14, testAiPartnerId: 14, testAiRightId: 14},
    deck: deck ?? DeckState(TichuTurn(TurnType.empty, []), CardFace.none),
    trickPoints: trickPoints,
    activeWish: activeWish,
    currentPlayerId: currentPlayerId ?? testAiLeftId,
    consecutivePasses: consecutivePasses,
    lastPlayedBy: lastPlayedBy,
    lastPlayedTurn: lastPlayedTurn,
    lastDragonGiveBy: lastDragonGiveBy,
    lastDragonGiveTo: lastDragonGiveTo,
    pendingDragonGiveBy: pendingDragonGiveBy,
    pendingDragonGiveTargets: pendingDragonGiveTargets ?? const [],
    pendingAiPlayerId: pendingAiPlayerId,
    pendingAiCards: pendingAiCards ?? const [],
    pendingAiPass: pendingAiPass,
    scoreState: scoreState ?? ScoreState.initial(),
    aiAwaitingConfirmation: aiAwaitingConfirmation,
    phase: GamePhase.play,
    grandTichuDecisions: const {},
    schupfCompletedPlayers: const [],
    schupfReceipts: schupfReceipts ?? const [],
  );
}
