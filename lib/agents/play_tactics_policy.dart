import 'package:tichu/agents/card_knowledge.dart';
import 'package:tichu/agents/table_relationships.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/card_utils.dart';
import 'package:tichu/game/turn/wish_logic.dart';

part 'play_tactics_extras.dart';

class PlayTacticsPolicy {
  const PlayTacticsPolicy();

  PassAction? selectPartnerSupportPass({
    required final String playerId,
    required final GameSnapshot snapshot,
    required final DeckState deck,
    required final List<Card> hand,
    required final TableRelationships table,
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
    final mustFulfillWish = mahJong(
      deck,
      TichuTurn(TurnType.none, const []),
      hand,
    );

    if (mustFulfillWish) {
      return null;
    }

    // A Tichu caller may need the lead back; no partner left: nothing to
    // support.
    if (selfCall != TichuCall.none || partnerCards <= 0 || !canPass) {
      return null;
    }

    final winnerId = deck.currentWinner.isNotEmpty
        ? deck.currentWinner
        : snapshot.lastPlayedBy;
    final partnerWinning = winnerId == partnerId;
    if (!partnerWinning) {
      return null;
    }

    if (partnerCall != TichuCall.none) {
      // Partner called: let them keep anything they can hold.
      if (!_isPartnerSupportPassTurn(
        deck.turn,
        CardKnowledge.of(snapshot, playerId),
      )) {
        return null;
      }
    } else if (deck.turn.type == TurnType.single &&
        deck.turn.value < Card.getValue(CardFace.ten)) {
      // Nobody called: only a low single is worth taking over from the
      // partner (cheap way to get the lead). Everything else: don't waste
      // cards (or the Dragon / a bomb) on a trick our team already holds.
      return null;
    }

    if (opponentTichuNearFinishWinning(
      playerId: playerId,
      snapshot: snapshot,
      deck: deck,
      table: table,
    )) {
      return null;
    }

    return PassAction(playerId: playerId);
  }

  bool _isPartnerSupportPassTurn(
    final TichuTurn turn,
    final CardKnowledge knowledge,
  ) {
    if (turn.type == TurnType.single) {
      // High single, or one nothing unseen can beat (e.g. a queen once all
      // kings, aces, dragon and phoenix are gone).
      return turn.value >= Card.getValue(CardFace.king) ||
          knowledge.isUnbeatable(turn);
    }

    return turn.type == TurnType.pair ||
        turn.type == TurnType.triplet ||
        turn.type == TurnType.fullHouse ||
        turn.type == TurnType.straight ||
        turn.type == TurnType.pairStraight ||
        turn.type == TurnType.bomb;
  }

  TichuTurn? selectPartnerFinishLead({
    required final GameSnapshot snapshot,
    required final List<TichuTurn> legalTurns,
    required final bool isLeading,
    required final TableRelationships table,
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
        .where((final turn) => turn.type == TurnType.single)
        .toList();
    if (singles.isEmpty) {
      return null;
    }

    singles.sort((final a, final b) => a.value.compareTo(b.value));
    final nonDragon = singles.where(
      (final turn) => !turn.cards.any((final c) => c.face == CardFace.dragon),
    );
    return nonDragon.isNotEmpty ? nonDragon.first : singles.first;
  }

  List<TichuTurn> wishPreferredTurns({
    required final List<TichuTurn> legalTurns,
    required final DeckState deck,
  }) {
    if (deck.wish == CardFace.none) {
      return const <TichuTurn>[];
    }
    return legalTurns
        .where(
          (final turn) =>
              turn.cards.any((final card) => card.face == deck.wish),
        )
        .toList();
  }

  List<TichuTurn> filterWishValidPlays({
    required final DeckState deck,
    required final List<TichuTurn> legalTurns,
    required final List<Card> hand,
  }) => legalTurns.where((final turn) => !mahJong(deck, turn, hand)).toList();

  TichuTurn? selectMahjongLeadTurn({
    required final List<TichuTurn> legalTurns,
    required final DeckState deck,
    required final List<Card> hand,
    required final bool isLeading,
    required final TichuTurn Function(List<TichuTurn>) selectPlay,
  }) {
    if (!isLeading || deck.wish != CardFace.none) {
      return null;
    }
    if (!hand.any((final c) => c.face == CardFace.mahJong)) {
      return null;
    }

    final mahjongTurns = legalTurns
        .where(
          (final turn) =>
              turn.cards.any((final c) => c.face == CardFace.mahJong),
        )
        .toList();
    if (mahjongTurns.isEmpty) {
      return null;
    }

    final mahjongStraights = mahjongTurns
        .where((final turn) => turn.type == TurnType.straight)
        .toList();
    if (mahjongStraights.isNotEmpty) {
      return selectPlay(mahjongStraights);
    }

    return selectPlay(mahjongTurns);
  }
}
