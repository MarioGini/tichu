import 'package:flutter/foundation.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/turn/tichu_data.dart';

@immutable
class DriverUiProjection {
  const DriverUiProjection({
    required this.pendingOpponentPlayerId,
    required this.pendingOpponentCards,
    required this.pendingOpponentPass,
    required this.selectedIndexes,
    required this.schupfToLeft,
    required this.schupfToPartner,
    required this.schupfToRight,
  });

  final String? pendingOpponentPlayerId;
  final List<Card> pendingOpponentCards;
  final bool pendingOpponentPass;
  final Set<int> selectedIndexes;
  final Card? schupfToLeft;
  final Card? schupfToPartner;
  final Card? schupfToRight;
}

class DriverUiProjector {
  const DriverUiProjector();

  DriverUiProjection project({
    required final PlayerSnapshot snapshot,
    required final String humanId,
    required final bool isSelfManual,
    required final List<Card> hand,
    required final Set<int> currentSelectedIndexes,
    required final Card? currentSchupfToLeft,
    required final Card? currentSchupfToPartner,
    required final Card? currentSchupfToRight,
  }) {
    // When the visible player is AI-controlled, their pending turn appears
    // as selected cards in the hand, not as a center-area overlay.
    final isAiSelfPending =
        !isSelfManual && snapshot.pendingOpponentPlayerId == humanId;

    final pendingOpponentPlayerId = isAiSelfPending
        ? null
        : snapshot.pendingOpponentPlayerId;
    final pendingOpponentCards = isAiSelfPending
        ? const <Card>[]
        : List<Card>.from(snapshot.pendingOpponentCards);
    final pendingOpponentPass =
        !isAiSelfPending && snapshot.pendingOpponentPass;

    final selectedIndexes = _projectSelectedIndexes(
      snapshot: snapshot,
      humanId: humanId,
      isSelfManual: isSelfManual,
      hand: hand,
      currentSelectedIndexes: currentSelectedIndexes,
    );

    final (schupfToLeft, schupfToPartner, schupfToRight) = _projectSchupfSlots(
      snapshot: snapshot,
      humanId: humanId,
      isSelfManual: isSelfManual,
      currentSchupfToLeft: currentSchupfToLeft,
      currentSchupfToPartner: currentSchupfToPartner,
      currentSchupfToRight: currentSchupfToRight,
    );

    return DriverUiProjection(
      pendingOpponentPlayerId: pendingOpponentPlayerId,
      pendingOpponentCards: pendingOpponentCards,
      pendingOpponentPass: pendingOpponentPass,
      selectedIndexes: selectedIndexes,
      schupfToLeft: schupfToLeft,
      schupfToPartner: schupfToPartner,
      schupfToRight: schupfToRight,
    );
  }

  Set<int> _projectSelectedIndexes({
    required final PlayerSnapshot snapshot,
    required final String humanId,
    required final bool isSelfManual,
    required final List<Card> hand,
    required final Set<int> currentSelectedIndexes,
  }) {
    if (isSelfManual) {
      return Set<int>.from(currentSelectedIndexes);
    }

    // AI-controlled visible player: show pending cards as selected in hand.
    final isPendingSelfPlay =
        snapshot.pendingOpponentPlayerId == humanId &&
        snapshot.pendingOpponentCards.isNotEmpty &&
        !snapshot.pendingOpponentPass;
    if (!isPendingSelfPlay) {
      return <int>{};
    }

    return _findSelectedIndexesForCards(hand, snapshot.pendingOpponentCards);
  }

  (Card?, Card?, Card?) _projectSchupfSlots({
    required final PlayerSnapshot snapshot,
    required final String humanId,
    required final bool isSelfManual,
    required final Card? currentSchupfToLeft,
    required final Card? currentSchupfToPartner,
    required final Card? currentSchupfToRight,
  }) {
    final isPendingSelfSchupf =
        snapshot.pendingOpponentPlayerId == humanId &&
        snapshot.pendingOpponentCards.length == 3;
    final inOwnSchupfPhase =
        snapshot.phase == GamePhase.schupf &&
        (!snapshot.schupfCompletedPlayers.contains(humanId) ||
            isPendingSelfSchupf);
    if (!inOwnSchupfPhase) {
      return (null, null, null);
    }

    if (isSelfManual) {
      return (
        currentSchupfToLeft,
        currentSchupfToPartner,
        currentSchupfToRight,
      );
    }

    if (isPendingSelfSchupf) {
      // UI labels map mirrored for the bottom player:
      // Left label reads schupfToRight, Right label reads schupfToLeft.
      return (
        snapshot.pendingOpponentCards[2],
        snapshot.pendingOpponentCards[1],
        snapshot.pendingOpponentCards[0],
      );
    }

    return (currentSchupfToLeft, currentSchupfToPartner, currentSchupfToRight);
  }

  Set<int> _findSelectedIndexesForCards(
    final List<Card> hand,
    final List<Card> selectedCards,
  ) {
    final indexes = <int>{};
    final used = <int>{};
    for (final selectedCard in selectedCards) {
      for (var i = 0; i < hand.length; i++) {
        if (used.contains(i)) continue;
        if (hand[i] != selectedCard) continue;
        indexes.add(i);
        used.add(i);
        break;
      }
    }
    return indexes;
  }
}
