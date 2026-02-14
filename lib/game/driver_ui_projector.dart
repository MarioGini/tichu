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
    required PlayerSnapshot snapshot,
    required String humanId,
    required bool isSelfManual,
    required List<Card> hand,
    required Set<int> currentSelectedIndexes,
    required Card? currentSchupfToLeft,
    required Card? currentSchupfToPartner,
    required Card? currentSchupfToRight,
  }) {
    final inPlayPhase = snapshot.phase == GamePhase.play;
    final pendingOpponentPlayerId = inPlayPhase
        ? snapshot.pendingOpponentPlayerId
        : null;
    final pendingOpponentCards = inPlayPhase
        ? List<Card>.from(snapshot.pendingOpponentCards)
        : const <Card>[];
    final pendingOpponentPass = inPlayPhase && snapshot.pendingOpponentPass;

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
    required PlayerSnapshot snapshot,
    required String humanId,
    required bool isSelfManual,
    required List<Card> hand,
    required Set<int> currentSelectedIndexes,
  }) {
    if (isSelfManual) {
      return Set<int>.from(currentSelectedIndexes);
    }

    final isPendingSelfPlay =
        snapshot.phase == GamePhase.play &&
        snapshot.pendingOpponentPlayerId == humanId &&
        snapshot.pendingOpponentCards.isNotEmpty &&
        !snapshot.pendingOpponentPass;
    if (!isPendingSelfPlay) {
      return <int>{};
    }

    return _findSelectedIndexesForCards(hand, snapshot.pendingOpponentCards);
  }

  (Card?, Card?, Card?) _projectSchupfSlots({
    required PlayerSnapshot snapshot,
    required String humanId,
    required bool isSelfManual,
    required Card? currentSchupfToLeft,
    required Card? currentSchupfToPartner,
    required Card? currentSchupfToRight,
  }) {
    final inOwnSchupfPhase =
        snapshot.phase == GamePhase.schupf &&
        !snapshot.schupfCompletedPlayers.contains(humanId);
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

    final isPendingSelfSchupf =
        snapshot.pendingOpponentPlayerId == humanId &&
        snapshot.pendingOpponentCards.length == 3;
    if (isPendingSelfSchupf) {
      return (
        snapshot.pendingOpponentCards[0],
        snapshot.pendingOpponentCards[1],
        snapshot.pendingOpponentCards[2],
      );
    }

    return (currentSchupfToLeft, currentSchupfToPartner, currentSchupfToRight);
  }

  Set<int> _findSelectedIndexesForCards(
    List<Card> hand,
    List<Card> selectedCards,
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
