import 'package:tichu/agents/table_relationships.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/card_utils.dart';
import 'package:tichu/game/turn/wish_logic.dart';

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

    if (partnerCall == TichuCall.none ||
        selfCall != TichuCall.none ||
        partnerCards <= 0 ||
        !canPass) {
      return null;
    }

    final winnerId = deck.currentWinner.isNotEmpty
        ? deck.currentWinner
        : snapshot.lastPlayedBy;
    final partnerWinning = winnerId == partnerId;
    if (!partnerWinning) {
      return null;
    }

    if (!_isPartnerSupportPassTurn(deck.turn)) {
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

  bool _isPartnerSupportPassTurn(final TichuTurn turn) {
    if (turn.type == TurnType.single) {
      return turn.value >= Card.getValue(CardFace.king);
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

  TichuTurn? selectEarlyDogLead({
    required final List<TichuTurn> legalTurns,
    required final bool isLeading,
  }) {
    if (!isLeading) {
      return null;
    }

    for (final turn in legalTurns) {
      if (turn.type == TurnType.dog ||
          turn.cards.any((final card) => card.face == CardFace.dog)) {
        return turn;
      }
    }

    return null;
  }

  TichuTurn? selectPartnerGrandTichuDogLead({
    required final String playerId,
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
    if (partnerCall != TichuCall.grandTichu) {
      return null;
    }

    if (snapshot.lastPlayedBy != playerId) {
      return null;
    }

    for (final turn in legalTurns) {
      if (turn.type == TurnType.dog ||
          turn.cards.any((final card) => card.face == CardFace.dog)) {
        return turn;
      }
    }

    return null;
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

  bool isHighWinningTrick(final TichuTurn turn) {
    if (turn.type == TurnType.bomb) {
      return true;
    }
    if (turn.cards.any((final card) => card.face == CardFace.dragon)) {
      return true;
    }
    return turn.value >= Card.getValue(CardFace.king);
  }

  bool opponentTichuNearFinishWinning({
    required final String playerId,
    required final GameSnapshot snapshot,
    required final DeckState deck,
    required final TableRelationships table,
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

  /// When responding to a single on the deck, prefer playing a card whose face
  /// appears only once in the hand (a true singleton) so that pairs and larger
  /// combos are preserved.  Returns the lowest such singleton, or `null` if
  /// none exists (in which case the caller falls through to the scorer).
  TichuTurn? selectSingletonResponse({
    required final List<TichuTurn> legalTurns,
    required final DeckState deck,
    required final List<Card> hand,
  }) {
    if (deck.turn.type != TurnType.single) return null;

    final singles = legalTurns
        .where((final t) => t.type == TurnType.single)
        .toList();
    if (singles.isEmpty) return null;

    // Count how many times each face appears in the hand (ignoring specials
    // like phoenix which can substitute for anything).
    final normalCards = hand
        .where(
          (final c) =>
              c.face != CardFace.phoenix &&
              c.face != CardFace.dog &&
              c.face != CardFace.dragon,
        )
        .toList();
    final occurrences = getOccurrenceCount(normalCards);

    final hasNaturalWinningSingle = singles.any((final t) {
      final face = t.cards.first.face;
      return face != CardFace.phoenix &&
          face != CardFace.dragon &&
          face != CardFace.dog;
    });

    // Filter to singles whose face is a true singleton in the hand.
    final singletonPlays = singles.where((final t) {
      final face = t.cards.first.face;
      // Dragon and dog are always fine to play. Preserve phoenix when a
      // natural winning single exists, since phoenix is our most flexible
      // remaining trump-like control card.
      if (face == CardFace.dragon || face == CardFace.dog) {
        return true;
      }
      if (face == CardFace.phoenix) {
        return !hasNaturalWinningSingle;
      }
      return (occurrences[face] ?? 0) == 1;
    }).toList();

    if (singletonPlays.isEmpty) return null;

    // Pick the lowest-value singleton.
    singletonPlays.sort((final a, final b) => a.value.compareTo(b.value));
    return singletonPlays.first;
  }
}
