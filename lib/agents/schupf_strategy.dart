import 'package:tichu/agents/tichu_call_strategy.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/bomb_utils.dart';

abstract class SchupfStrategy {
  Future<SchupfAction> selectSchupfCards(
    GameSnapshot snapshot,
    String playerId,
  );
}

class DefaultSchupfStrategy implements SchupfStrategy {
  /// The call thresholds that decide whether to keep strong cards (a hand
  /// the bot will call Tichu with).
  final DefaultTichuCallStrategy calls;

  const DefaultSchupfStrategy({this.calls = const DefaultTichuCallStrategy()});

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
    bool called(String? id) =>
        id != null && (tichuCalls[id] ?? TichuCall.none) != TichuCall.none;
    // "Going out first" intent: an actual (Grand) Tichu call, or — for me —
    // a hand the heuristic would call Tichu with after the exchange.
    final selfGoing = called(playerId) || calls.isTichuHand(hand);
    final partnerGrand = called(partnerId);
    final leftGrand = called(leftId);
    final rightGrand = called(rightId);

    Card? toLeft;
    Card? toRight;

    // If an opponent called (Grand) Tichu, prefer giving them the Dog.
    // If partner called, keep Dog for support plays.
    if (!partnerGrand &&
        (leftGrand || rightGrand) &&
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

    // Fill the opponent slots with low cards: odd ranks to the left, even
    // ranks to the right. Both partners follow this convention, so an
    // opponent never gets two cards of the same rank from us (no bomb gift).
    // Never break up a bomb (four of a kind / straight flush) when any other
    // card can be passed instead.
    final bombCards = <Card>{
      for (final bomb in getBombs(List<Card>.from(hand))) ...bomb.cards,
    };
    List<Card> safe(List<Card> pool) {
      final kept = [
        for (final c in pool)
          if (!bombCards.any((b) => b.face == c.face && b.color == c.color)) c,
      ];
      return kept.isEmpty ? pool : kept;
    }

    final normalPool = safe(_normalCandidates(remaining));
    if (toLeft == null) {
      final pick =
          _pickLowestByParity(normalPool, isEven: false) ??
          _pickLowest(safe(remaining), avoidDog: partnerGrand);
      toLeft = pick;
      remaining.remove(pick);
    }
    if (toRight == null) {
      final updatedNormal = safe(_normalCandidates(remaining));
      final pick =
          _pickLowestByParity(updatedNormal, isEven: true) ??
          _pickLowest(safe(remaining), avoidDog: partnerGrand);
      toRight = pick;
      remaining.remove(pick);
    }

    // Partner card strategy:
    // - Partner called (Grand) Tichu: give strongest non-Dog card if possible.
    // - I called, or my hand is a Tichu hand: keep strength, give a low card.
    // - Otherwise: give strongest regular card (support the partner).
    Card toPartner;
    if (partnerGrand) {
      final nonDog = safe(remaining)
          .where((c) => c.face != CardFace.dog)
          .toList();
      if (nonDog.isNotEmpty) {
        nonDog.sort((a, b) => b.value.compareTo(a.value));
        toPartner = nonDog.first;
      } else {
        remaining.sort((a, b) => b.value.compareTo(a.value));
        toPartner = remaining.first;
      }
    } else if (selfGoing) {
      final normal = _normalCandidates(remaining);
      toPartner = _pickLowest(normal.isNotEmpty ? normal : remaining);
    } else {
      final partnerPool = safe(_normalCandidates(remaining));
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

  List<Card> _normalCandidates(List<Card> hand) => hand
      .where(
        (c) =>
            c.face != CardFace.dragon &&
            c.face != CardFace.phoenix &&
            c.face != CardFace.dog &&
            c.face != CardFace.mahJong,
      )
      .toList();

  Card _pickLowest(List<Card> pool, {bool avoidDog = false}) {
    final candidates = avoidDog
        ? pool.where((card) => card.face != CardFace.dog).toList()
        : List<Card>.from(pool);
    if (candidates.isEmpty) {
      candidates.addAll(pool);
    }
    candidates.sort((a, b) => a.value.compareTo(b.value));
    return candidates.first;
  }

  static const double _maxParityValue = 10;

  Card? _pickLowestByParity(List<Card> pool, {required bool isEven}) {
    // Only low cards: never hand an opponent a high card just for parity.
    final candidates = pool
        .where(
          (c) => c.value.toInt().isEven == isEven && c.value <= _maxParityValue,
        )
        .toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => a.value.compareTo(b.value));
    return candidates.first;
  }
}
