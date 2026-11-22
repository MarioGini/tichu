import 'package:tichu/agents/nn/feature_encoder.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/round_log.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'ai_test_fixtures.dart';

Card c(final CardFace face, [final CardColor color = CardColor.black]) =>
    Card(face, color);

GameSnapshot fxSnapshot({
  required final List<Card> mine,
  required final Map<String, List<Card>> others,
  final DeckState? deck,
  final int trickPoints = 0,
  final List<String> finishOrder = const [],
  final Map<String, TichuCall> calls = const {},
  final Map<String, List<SchupfReceipt>> receipts = const {},
  final List<RoundLogEntry> roundLog = const [],
  final Map<String, SchupfAction> schupfSelections = const {},
}) {
  final base = aiSnapshot(
    myHand: mine,
    otherHands: others,
    deck: deck,
    tichuCalls: calls,
    schupfReceipts: receipts,
  );
  return GameSnapshot(
    gameId: base.gameId,
    players: base.players,
    hands: base.hands,
    deck: base.deck,
    trickPoints: trickPoints,
    activeWish: base.activeWish,
    currentPlayerId: base.currentPlayerId,
    consecutivePasses: base.consecutivePasses,
    lastPlayedBy: base.lastPlayedBy,
    lastPlayedTurn: base.lastPlayedTurn,
    lastDragonGiveBy: null,
    lastDragonGiveTo: null,
    pendingDragonGiveBy: null,
    pendingDragonGiveTargets: const [],
    pendingOpponentPlayerId: null,
    pendingOpponentCards: const [],
    pendingOpponentPass: false,
    scoreState: base.scoreState.copyWith(finishOrder: finishOrder),
    opponentAwaitingConfirmation: false,
    phase: GamePhase.play,
    grandTichuDecisions: const {},
    schupfCompletedPlayers: const [],
    schupfReceipts: base.schupfReceipts,
    schupfSelections: schupfSelections,
    roundLog: roundLog,
  );
}

int slot(final String group, final int i) => switch (group) {
  'hand' => handOffset + i,
  'played' => playedOffset + i,
  'unseen' => unseenOffset + i,
  'trick' => trickOffset + i,
  'seats' => seatsOffset + i,
  'self' => selfOffset + i,
  'history' => historyOffset + i,
  'claim' => claimOffset + i,
  'received' => receivedOffset + i,
  _ => throw ArgumentError(group),
};
