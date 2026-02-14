import 'package:tichu/game/game_backend.dart';
import 'package:tichu/agents/table_relationships.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/wish_logic.dart';

class PlayTacticsPolicy {
  const PlayTacticsPolicy();

  PassAction? selectPartnerSupportPass({
    required String playerId,
    required GameSnapshot snapshot,
    required DeckState deck,
    required List<Card> hand,
    required TableRelationships table,
  }) {
    final partnerId = table.partnerId;
    if (partnerId == null) {
      return null;
    }

    final partnerCall =
        snapshot.scoreState.tichuCalls[partnerId] ?? TichuCall.none;
    final selfCall = snapshot.scoreState.tichuCalls[playerId] ?? TichuCall.none;
    final partnerCards = (snapshot.hands[partnerId] ?? const <Card>[]).length;
    final canPass =
        deck.turn.type != TurnType.empty &&
        deck.turn.type != TurnType.none &&
        deck.turn.type != TurnType.dog;
    final mustFulfillWish = mahJong(deck, TichuTurn(TurnType.none, []), hand);

    if (mustFulfillWish) {
      return null;
    }

    if (partnerCall != TichuCall.none &&
        selfCall == TichuCall.none &&
        partnerCards > 0 &&
        canPass) {
      return PassAction(playerId: playerId);
    }

    final partnerWinning =
        snapshot.lastPlayedBy == partnerId || deck.currentWinner == partnerId;
    if (partnerWinning &&
        isHighWinningTrick(deck.turn) &&
        hand.length > 1 &&
        deck.turn.type != TurnType.empty &&
        deck.turn.type != TurnType.none &&
        !opponentTichuNearFinishWinning(
          playerId: playerId,
          snapshot: snapshot,
          deck: deck,
          table: table,
        )) {
      return PassAction(playerId: playerId);
    }

    if (partnerCall != TichuCall.none &&
        snapshot.lastPlayedBy == partnerId &&
        partnerCards <= 5 &&
        hand.length > 1 &&
        deck.turn.type != TurnType.empty &&
        deck.turn.type != TurnType.none) {
      return PassAction(playerId: playerId);
    }

    return null;
  }

  TichuTurn? selectPartnerFinishLead({
    required GameSnapshot snapshot,
    required List<TichuTurn> legalTurns,
    required bool isLeading,
    required TableRelationships table,
  }) {
    if (!isLeading) {
      return null;
    }

    final partnerId = table.partnerId;
    if (partnerId == null) {
      return null;
    }

    final partnerCall =
        snapshot.scoreState.tichuCalls[partnerId] ?? TichuCall.none;
    final partnerCards = (snapshot.hands[partnerId] ?? const <Card>[]).length;
    if (partnerCall == TichuCall.none || partnerCards != 1) {
      return null;
    }

    final singles = legalTurns
        .where((turn) => turn.type == TurnType.single)
        .toList();
    if (singles.isEmpty) {
      return null;
    }

    singles.sort((a, b) => a.value.compareTo(b.value));
    final nonDragon = singles.where(
      (turn) => !turn.cards.any((c) => c.face == CardFace.dragon),
    );
    return nonDragon.isNotEmpty ? nonDragon.first : singles.first;
  }

  TichuTurn? selectPartnerGrandTichuDogLead({
    required String playerId,
    required GameSnapshot snapshot,
    required List<TichuTurn> legalTurns,
    required bool isLeading,
    required TableRelationships table,
  }) {
    if (!isLeading) {
      return null;
    }

    final partnerId = table.partnerId;
    if (partnerId == null) {
      return null;
    }

    final partnerCall =
        snapshot.scoreState.tichuCalls[partnerId] ?? TichuCall.none;
    if (partnerCall != TichuCall.grandTichu) {
      return null;
    }

    if (snapshot.lastPlayedBy != playerId) {
      return null;
    }

    for (final turn in legalTurns) {
      if (turn.type == TurnType.dog ||
          turn.cards.any((card) => card.face == CardFace.dog)) {
        return turn;
      }
    }

    return null;
  }

  List<TichuTurn> wishPreferredTurns({
    required List<TichuTurn> legalTurns,
    required DeckState deck,
  }) {
    if (deck.wish == CardFace.none) {
      return const <TichuTurn>[];
    }
    return legalTurns
        .where((turn) => turn.cards.any((card) => card.face == deck.wish))
        .toList();
  }

  List<TichuTurn> filterWishValidPlays({
    required DeckState deck,
    required List<TichuTurn> legalTurns,
    required List<Card> hand,
  }) {
    return legalTurns.where((turn) => !mahJong(deck, turn, hand)).toList();
  }

  TichuTurn? selectMahjongLeadTurn({
    required List<TichuTurn> legalTurns,
    required DeckState deck,
    required List<Card> hand,
    required bool isLeading,
    required TichuTurn Function(List<TichuTurn>) selectPlay,
  }) {
    if (!isLeading || deck.wish != CardFace.none) {
      return null;
    }
    if (!hand.any((c) => c.face == CardFace.mahJong)) {
      return null;
    }

    final mahjongTurns = legalTurns
        .where((turn) => turn.cards.any((c) => c.face == CardFace.mahJong))
        .toList();
    if (mahjongTurns.isEmpty) {
      return null;
    }

    final mahjongStraights = mahjongTurns
        .where((turn) => turn.type == TurnType.straight)
        .toList();
    if (mahjongStraights.isNotEmpty) {
      return selectPlay(mahjongStraights);
    }

    return selectPlay(mahjongTurns);
  }

  bool isHighWinningTrick(TichuTurn turn) {
    if (turn.type == TurnType.bomb) {
      return true;
    }
    if (turn.cards.any((card) => card.face == CardFace.dragon)) {
      return true;
    }
    return turn.value >= Card.getValue(CardFace.king);
  }

  bool opponentTichuNearFinishWinning({
    required String playerId,
    required GameSnapshot snapshot,
    required DeckState deck,
    required TableRelationships table,
  }) {
    final winnerId = deck.currentWinner.isNotEmpty
        ? deck.currentWinner
        : snapshot.lastPlayedBy;
    if (winnerId == null || winnerId == playerId) {
      return false;
    }
    if (!table.isOpponent(winnerId)) {
      return false;
    }

    final call = snapshot.scoreState.tichuCalls[winnerId] ?? TichuCall.none;
    if (call == TichuCall.none) {
      return false;
    }
    final cardsLeft = (snapshot.hands[winnerId] ?? const <Card>[]).length;
    return cardsLeft > 0 && cardsLeft <= 2;
  }
}
