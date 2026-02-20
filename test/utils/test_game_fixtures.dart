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
  final List<Card>? hand,
  final DeckState? deck,
  final String? currentPlayerId,
  final String? pendingOpponentPlayerId,
  final List<Card>? pendingOpponentCards,
  final bool pendingOpponentPass = false,
  final bool opponentAwaitingConfirmation = false,
  final bool canCallTichu = false,
  final Map<String, int>? opponentCardCounts,
  final CardFace activeWish = CardFace.none,
  final int trickPoints = 0,
  final int consecutivePasses = 0,
  final String? lastPlayedBy,
  final TichuTurn? lastPlayedTurn,
  final String? lastDragonGiveBy,
  final String? lastDragonGiveTo,
  final String? pendingDragonGiveBy,
  final List<String>? pendingDragonGiveTargets,
  final ScoreState? scoreState,
  final GamePhase phase = GamePhase.play,
  final List<String>? schupfCompletedPlayers,
  final List<SchupfReceipt>? schupfReceipts,
}) => PlayerSnapshot(
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
    deck: deck ?? DeckState(TichuTurn(TurnType.empty, const []), CardFace.none),
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
    canCallTichu: canCallTichu,
    grandTichuDecisions: const {},
    schupfCompletedPlayers: schupfCompletedPlayers ?? const [],
    schupfReceipts: schupfReceipts ?? const [],
  );
