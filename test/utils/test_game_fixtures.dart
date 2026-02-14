import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

const testHumanId = 'player-0';
const testOpponentLeftId = 'player-1';
const testOpponentPartnerId = 'player-2';
const testOpponentRightId = 'player-3';

final testPlayers = [
  const GamePlayer(
    id: testHumanId,
    name: 'You',
    seat: 0,
    type: PlayerType.human,
  ),
  const GamePlayer(
    id: testOpponentLeftId,
    name: 'Opponent 1',
    seat: 1,
    type: PlayerType.automated,
  ),
  const GamePlayer(
    id: testOpponentPartnerId,
    name: 'Opponent 2 (Partner)',
    seat: 2,
    type: PlayerType.automated,
  ),
  const GamePlayer(
    id: testOpponentRightId,
    name: 'Opponent 3',
    seat: 3,
    type: PlayerType.automated,
  ),
];

PlayerSnapshot buildPlayerSnapshot({
  List<Card>? hand,
  DeckState? deck,
  String? currentPlayerId,
  String? pendingOpponentPlayerId,
  List<Card>? pendingOpponentCards,
  bool pendingOpponentPass = false,
  bool opponentAwaitingConfirmation = false,
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
  GamePhase phase = GamePhase.play,
  List<String>? schupfCompletedPlayers,
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
        const {
          testOpponentLeftId: 14,
          testOpponentPartnerId: 14,
          testOpponentRightId: 14,
        },
    deck: deck ?? DeckState(TichuTurn(TurnType.empty, []), CardFace.none),
    trickPoints: trickPoints,
    activeWish: activeWish,
    currentPlayerId: currentPlayerId ?? testOpponentLeftId,
    consecutivePasses: consecutivePasses,
    lastPlayedBy: lastPlayedBy,
    lastPlayedTurn: lastPlayedTurn,
    lastDragonGiveBy: lastDragonGiveBy,
    lastDragonGiveTo: lastDragonGiveTo,
    pendingDragonGiveBy: pendingDragonGiveBy,
    pendingDragonGiveTargets: pendingDragonGiveTargets ?? const [],
    pendingOpponentPlayerId: pendingOpponentPlayerId,
    pendingOpponentCards: pendingOpponentCards ?? const [],
    pendingOpponentPass: pendingOpponentPass,
    scoreState: scoreState ?? ScoreState.initial(),
    opponentAwaitingConfirmation: opponentAwaitingConfirmation,
    phase: phase,
    grandTichuDecisions: const {},
    schupfCompletedPlayers: schupfCompletedPlayers ?? const [],
    schupfReceipts: schupfReceipts ?? const [],
  );
}
