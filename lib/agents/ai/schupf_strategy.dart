import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

abstract class SchupfStrategy {
  Future<SchupfAction> selectSchupfCards(
    GameSnapshot snapshot,
    String playerId,
  );
}

class DefaultSchupfStrategy implements SchupfStrategy {
  const DefaultSchupfStrategy();

  @override
  Future<SchupfAction> selectSchupfCards(
    GameSnapshot snapshot,
    String playerId,
  ) async {
    final hand = List<Card>.from(snapshot.hands[playerId] ?? const <Card>[]);
    if (hand.length < 3) {
      throw StateError('Not enough cards to schupf.');
    }

    final (toLeft, toPartner, toRight) = _selectSchupfCards(
      snapshot,
      playerId,
      hand,
    );

    return SchupfAction(
      playerId: playerId,
      toLeft: toLeft,
      toPartner: toPartner,
      toRight: toRight,
    );
  }

  (Card toLeft, Card toPartner, Card toRight) _selectSchupfCards(
    GameSnapshot snapshot,
    String playerId,
    List<Card> hand,
  ) {
    final remaining = List<Card>.from(hand)
      ..sort((a, b) => a.value.compareTo(b.value));

    final (leftId, partnerId, rightId) = _seatIds(snapshot, playerId);
    final tichuCalls = snapshot.scoreState.tichuCalls;
    final partnerGrand =
        partnerId != null && tichuCalls[partnerId] == TichuCall.grandTichu;
    final leftGrand =
        leftId != null && tichuCalls[leftId] == TichuCall.grandTichu;
    final rightGrand =
        rightId != null && tichuCalls[rightId] == TichuCall.grandTichu;

    Card? toLeft;
    Card? toRight;

    // If an opponent called Grand Tichu, prefer giving them the Dog.
    if ((leftGrand || rightGrand) &&
        remaining.any((c) => c.face == CardFace.dog)) {
      final dogIndex = remaining.indexWhere((c) => c.face == CardFace.dog);
      if (dogIndex != -1) {
        final dogCard = remaining.removeAt(dogIndex);
        if (leftGrand) {
          toLeft = dogCard;
        } else {
          toRight = dogCard;
        }
      }
    }

    // Prefer splitting low pairs to opponents (reduces bomb potential).
    if (toLeft == null && toRight == null) {
      final pairFace = _lowestPairFace(remaining, maxValue: 7);
      if (pairFace != null) {
        final pairCards = remaining
            .where((c) => c.face == pairFace)
            .take(2)
            .toList();
        if (pairCards.length == 2) {
          toLeft = pairCards.first;
          toRight = pairCards.last;
          remaining.remove(toLeft);
          remaining.remove(toRight);
        }
      }
    }

    // Fill any missing opponent slots with low cards, preferring odd to left
    // and even to right to reduce overlap with partner.
    final normalPool = _normalCandidates(remaining);
    if (toLeft == null) {
      final pick =
          _pickLowestByParity(normalPool, isEven: false) ??
          _pickLowest(remaining);
      toLeft = pick;
      remaining.remove(pick);
    }
    if (toRight == null) {
      final updatedNormal = _normalCandidates(remaining);
      final pick =
          _pickLowestByParity(updatedNormal, isEven: true) ??
          _pickLowest(remaining);
      toRight = pick;
      remaining.remove(pick);
    }

    // Partner card: if partner called Grand Tichu, give the best available.
    Card toPartner;
    if (partnerGrand) {
      remaining.sort((a, b) => b.value.compareTo(a.value));
      toPartner = remaining.first;
    } else {
      final partnerPool = _normalCandidates(remaining);
      if (partnerPool.isNotEmpty) {
        partnerPool.sort((a, b) => b.value.compareTo(a.value));
        toPartner = partnerPool.first;
      } else {
        remaining.sort((a, b) => b.value.compareTo(a.value));
        toPartner = remaining.first;
      }
    }

    return (toLeft, toPartner, toRight);
  }

  (String? leftId, String? partnerId, String? rightId) _seatIds(
    GameSnapshot snapshot,
    String playerId,
  ) {
    final mySeat = snapshot.players.firstWhere((p) => p.id == playerId).seat;
    final leftSeat = (mySeat + 1) % 4;
    final rightSeat = (mySeat + 3) % 4;
    String? leftId;
    String? rightId;
    String? partnerId;
    for (final player in snapshot.players) {
      if (player.seat == leftSeat) leftId = player.id;
      if (player.seat == rightSeat) rightId = player.id;
      if (player.id != playerId && player.seat % 2 == mySeat % 2) {
        partnerId = player.id;
      }
    }
    return (leftId, partnerId, rightId);
  }

  List<Card> _normalCandidates(List<Card> hand) {
    return hand
        .where(
          (c) =>
              c.face != CardFace.dragon &&
              c.face != CardFace.phoenix &&
              c.face != CardFace.dog &&
              c.face != CardFace.mahJong,
        )
        .toList();
  }

  Card _pickLowest(List<Card> pool) {
    pool.sort((a, b) => a.value.compareTo(b.value));
    return pool.first;
  }

  Card? _pickLowestByParity(List<Card> pool, {required bool isEven}) {
    final candidates = pool
        .where((c) => c.value.toInt().isEven == isEven)
        .toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => a.value.compareTo(b.value));
    return candidates.first;
  }

  CardFace? _lowestPairFace(List<Card> hand, {required int maxValue}) {
    final counts = <CardFace, int>{};
    for (final card in hand) {
      if (card.face == CardFace.dragon ||
          card.face == CardFace.phoenix ||
          card.face == CardFace.dog ||
          card.face == CardFace.mahJong) {
        continue;
      }
      counts[card.face] = (counts[card.face] ?? 0) + 1;
    }
    final sortedFaces = counts.keys.toList()
      ..sort((a, b) => Card.getValue(a).compareTo(Card.getValue(b)));
    for (final face in sortedFaces) {
      if ((counts[face] ?? 0) >= 2 && Card.getValue(face) <= maxValue) {
        return face;
      }
    }
    return null;
  }
}
