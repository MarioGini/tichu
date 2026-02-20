import 'package:tichu/game/engine_state.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/engine/hand_utils.dart';

void applySchupfSelection(final GameEngineState state, final SchupfAction action) {
  if (state.schupfSelections.containsKey(action.playerId)) {
    return;
  }

  final hand = state.hands[action.playerId] ?? <Card>[];
  var resolvedAction = action;
  var selected = [action.toLeft, action.toPartner, action.toRight];
  if (!handContainsAll(hand, selected)) {
    final (toLeft, toPartner, toRight) = fallbackSchupf(hand);
    resolvedAction = SchupfAction(
      playerId: action.playerId,
      toLeft: toLeft,
      toPartner: toPartner,
      toRight: toRight,
    );
    selected = [toLeft, toPartner, toRight];
    if (!handContainsAll(hand, selected)) {
      throw StateError('Schupf cards are not in hand.');
    }
  }

  state.schupfSelections[action.playerId] = resolvedAction;
  _maybeFinalizeSchupf(state);
}

void applyAcknowledgeSchupf(
  final GameEngineState state,
  final AcknowledgeSchupfAction action,
) {
  state.schupfReceipts.remove(action.playerId);
}

bool hasPendingSchupfReceiptsForPlayer(final GameEngineState state, final String playerId) {
  final player = state.players.firstWhere(
    (final p) => p.id == playerId,
    orElse: () => state.players.first,
  );
  if (player.type != PlayerType.human) return false;
  final receipts = state.schupfReceipts[playerId];
  return receipts != null && receipts.isNotEmpty;
}

bool hasPendingHumanSchupfReceipts(final GameEngineState state) {
  for (final player in state.players) {
    if (player.type != PlayerType.human) continue;
    final receipts = state.schupfReceipts[player.id];
    if (receipts != null && receipts.isNotEmpty) {
      return true;
    }
  }
  return false;
}

void _maybeFinalizeSchupf(final GameEngineState state) {
  if (state.schupfSelections.length < state.players.length) {
    return;
  }

  final seatToPlayer = {
    for (final player in state.players) player.seat: player.id,
  };
  final idToSeat = {for (final player in state.players) player.id: player.seat};
  final additions = <String, List<Card>>{};
  final receipts = <String, List<SchupfReceipt>>{};

  for (final entry in state.schupfSelections.entries) {
    final sourceId = entry.key;
    final selection = entry.value;
    final sourcePlayer = state.players.firstWhere((final p) => p.id == sourceId);
    final leftId = seatToPlayer[(sourcePlayer.seat + 1) % 4]!;
    final partnerId = seatToPlayer[(sourcePlayer.seat + 2) % 4]!;
    final rightId = seatToPlayer[(sourcePlayer.seat + 3) % 4]!;

    final sourceHand = state.hands[sourceId] ?? <Card>[];
    removeCardsFromHand(sourceHand, [
      selection.toLeft,
      selection.toPartner,
      selection.toRight,
    ]);

    additions.putIfAbsent(leftId, () => <Card>[]).add(selection.toLeft);
    additions.putIfAbsent(partnerId, () => <Card>[]).add(selection.toPartner);
    additions.putIfAbsent(rightId, () => <Card>[]).add(selection.toRight);

    _addSchupfReceipt(
      receipts,
      recipientId: leftId,
      fromPlayerId: sourceId,
      direction: _schupfDirectionForRecipient(idToSeat, sourceId, leftId),
      card: selection.toLeft,
    );
    _addSchupfReceipt(
      receipts,
      recipientId: partnerId,
      fromPlayerId: sourceId,
      direction: _schupfDirectionForRecipient(idToSeat, sourceId, partnerId),
      card: selection.toPartner,
    );
    _addSchupfReceipt(
      receipts,
      recipientId: rightId,
      fromPlayerId: sourceId,
      direction: _schupfDirectionForRecipient(idToSeat, sourceId, rightId),
      card: selection.toRight,
    );
  }

  for (final entry in additions.entries) {
    final hand = state.hands[entry.key];
    hand?.addAll(entry.value);
  }

  state.schupfSelections.clear();
  state.schupfReceipts
    ..clear()
    ..addAll(receipts);
  state.phase = GamePhase.play;
  state.deck = DeckState(TichuTurn(TurnType.empty, const []), state.deck.wish);
  state.consecutivePasses = 0;
  state.lastPlayedBy = null;
  state.lastPlayedTurn = null;
  state.currentPlayerIndex = _startingPlayerIndex(state);
}

SchupfDirection _schupfDirectionForRecipient(
  final Map<String, int> idToSeat,
  final String fromPlayerId,
  final String recipientId,
) {
  final fromSeat = idToSeat[fromPlayerId] ?? 0;
  final recipientSeat = idToSeat[recipientId] ?? 0;
  if (fromSeat == (recipientSeat + 1) % 4) {
    return SchupfDirection.left;
  }
  if (fromSeat == (recipientSeat + 2) % 4) {
    return SchupfDirection.partner;
  }
  return SchupfDirection.right;
}

void _addSchupfReceipt(
  final Map<String, List<SchupfReceipt>> receipts, {
  required final String recipientId,
  required final String fromPlayerId,
  required final SchupfDirection direction,
  required final Card card,
}) {
  receipts
      .putIfAbsent(recipientId, () => <SchupfReceipt>[])
      .add(
        SchupfReceipt(
          card: card,
          fromPlayerId: fromPlayerId,
          direction: direction,
        ),
      );
}

int _startingPlayerIndex(final GameEngineState state) {
  for (var i = 0; i < state.players.length; i++) {
    final playerId = state.players[i].id;
    final hand = state.hands[playerId] ?? const <Card>[];
    if (hand.any((final card) => card.face == CardFace.mahJong)) {
      return i;
    }
  }
  return 0;
}
