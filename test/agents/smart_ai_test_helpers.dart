import 'package:tichu/agents/play_tactics_policy.dart';
import 'package:tichu/agents/schupf_strategy.dart';
import 'package:tichu/agents/table_relationships.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

const aiId = 'ai-0';
const partnerId = 'ai-2';
const leftId = 'ai-1';
const rightId = 'ai-3';

final aiPlayers = [
  const GamePlayer(id: aiId, name: 'AI-0', seat: 0, type: PlayerType.automated),
  const GamePlayer(
    id: leftId,
    name: 'AI-1',
    seat: 1,
    type: PlayerType.automated,
  ),
  const GamePlayer(
    id: partnerId,
    name: 'AI-2',
    seat: 2,
    type: PlayerType.automated,
  ),
  const GamePlayer(
    id: rightId,
    name: 'AI-3',
    seat: 3,
    type: PlayerType.automated,
  ),
];

GameSnapshot aiSnapshot({
  required final List<Card> myHand,
  final DeckState? deck,
  final Map<String, List<Card>>? otherHands,
  final Map<String, TichuCall>? tichuCalls,
  final String? lastPlayedBy,
  final TichuTurn? lastPlayedTurn,
  final CardFace? activeWish,
}) {
  final hands = <String, List<Card>>{
    aiId: myHand,
    leftId: otherHands?[leftId] ?? defaultHand(),
    partnerId: otherHands?[partnerId] ?? defaultHand(),
    rightId: otherHands?[rightId] ?? defaultHand(),
  };
  final scoreState = ScoreState.initial().copyWith(
    tichuCalls: tichuCalls ?? const {},
  );
  return GameSnapshot(
    gameId: 'test-game',
    players: aiPlayers,
    hands: hands,
    deck: deck ?? emptyDeck(),
    trickPoints: 0,
    activeWish: activeWish ?? deck?.wish ?? CardFace.none,
    currentPlayerId: aiId,
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

DeckState emptyDeck() =>
    DeckState(TichuTurn(TurnType.empty, const []), CardFace.none);

List<Card> defaultHand() => [
  Card(CardFace.two, CardColor.red),
  Card(CardFace.five, CardColor.blue),
  Card(CardFace.eight, CardColor.green),
  Card(CardFace.jack, CardColor.black),
  Card(CardFace.king, CardColor.red),
];

class FixedSchupfStrategy implements SchupfStrategy {
  const FixedSchupfStrategy({
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

class ForceEmptyValidPlaysPolicy extends PlayTacticsPolicy {
  const ForceEmptyValidPlaysPolicy();

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
