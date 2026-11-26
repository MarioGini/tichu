import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/turn_handler.dart';
import 'package:tichu/game/turn/utils/bomb_utils.dart';
import 'package:tichu/game/turn/utils/card_utils.dart';
import 'package:tichu/game/turn/utils/full_house_utils.dart';
import 'package:tichu/game/turn/utils/pair_straight_utils.dart';
import 'package:tichu/game/turn/utils/straight_utils.dart';

List<TichuTurn> generateLegalTurns(DeckState deck, List<Card> hand) {
  final turns = <TichuTurn>[];
  final handCopy = List<Card>.from(hand);

  if (deck.turn.type == TurnType.none ||
      deck.turn.type == TurnType.empty ||
      deck.turn.type == TurnType.dog) {
    turns.addAll(_generateAnyTurns(handCopy));
    return turns;
  }

  switch (deck.turn.type) {
    case TurnType.single:
      turns.addAll(_generateSingles(handCopy, deck));
    case TurnType.pair:
      turns.addAll(_generatePairs(handCopy, deck));
    case TurnType.triplet:
      turns.addAll(_generateTriplets(handCopy, deck));
    case TurnType.straight:
      turns.addAll(
        _plainStraights(
          getStraights(handCopy, deck.turn.cards.length),
          hand,
        ).where((turn) => validTurn(deck.turn, turn)),
      );
    case TurnType.pairStraight:
      turns.addAll(
        getPairStraights(
          handCopy,
          deck.turn.cards.length,
        ).where((turn) => validTurn(deck.turn, turn)),
      );
    case TurnType.fullHouse:
      turns.addAll(
        getFullHouses(handCopy).where((turn) => validTurn(deck.turn, turn)),
      );
    case TurnType.bomb:
      turns.addAll(
        getBombs(handCopy).where((turn) => validTurn(deck.turn, turn)),
      );
    case TurnType.dog:
    case TurnType.empty:
    case TurnType.none:
      break;
  }

  // Bombs can always be played on any trick type (Tichu rules).
  // Add them if we haven't already (i.e. not already in the bomb case).
  if (deck.turn.type != TurnType.bomb) {
    turns.addAll(getBombs(List<Card>.from(hand)));
  }

  return turns;
}

List<TichuTurn> _generateAnyTurns(List<Card> hand) {
  final turns = <TichuTurn>[];

  turns.addAll(_generateSingles(hand, null));
  turns.addAll(_generatePairs(hand, null));
  turns.addAll(_generateTriplets(hand, null));
  turns.addAll(_generateAnyStraights(hand));
  turns.addAll(_generateAnyPairStraights(hand));
  turns.addAll(getFullHouses(List<Card>.from(hand)));
  turns.addAll(getBombs(List<Card>.from(hand)));

  return turns;
}

// Same as getStraights(hand, length) for length = 5, 6, ...; the
// candidates do not depend on the length, so they are built once.
List<TichuTurn> _generateAnyStraights(List<Card> hand) {
  final turns = <TichuTurn>[];
  final maxLength = hand.length;
  if (maxLength < 5) return turns;
  final candidates = allStraightCandidates(hand);
  for (var length = 5; length <= maxLength; length += 1) {
    turns.addAll(straightsOfLength(candidates, length));
  }
  return _plainStraights(turns, hand);
}

/// A straight in one suit is a bomb (listed with the bombs), never a plain
/// straight. Where another card of the same rank breaks the suit, that is
/// the plain straight; otherwise there is none.
List<TichuTurn> _plainStraights(List<TichuTurn> straights, List<Card> hand) => [
  for (final straight in straights)
    if (_inOneSuit(straight.cards)) ?_breakSuit(straight, hand) else straight,
];

bool _inOneSuit(List<Card> cards) =>
    cards.every((c) => c.color != CardColor.special) &&
    cards.every((c) => c.color == cards.first.color);

TichuTurn? _breakSuit(TichuTurn straight, List<Card> hand) {
  for (var i = straight.cards.length - 1; i >= 0; i--) {
    final card = straight.cards[i];
    for (final other in hand) {
      if (other.face == card.face && other.color != card.color) {
        final cards = [...straight.cards]..[i] = other;
        return TichuTurn(TurnType.straight, cards);
      }
    }
  }
  return null;
}

// Same as getPairStraights(hand, length) for length = 4, 6, ...
List<TichuTurn> _generateAnyPairStraights(List<Card> hand) {
  final turns = <TichuTurn>[];
  final maxLength = hand.length;
  if (maxLength < 4) return turns;
  final candidates = allPairStraightCandidates(hand);
  for (var length = 4; length <= maxLength; length += 2) {
    turns.addAll(pairStraightsOfLength(candidates, length));
  }
  return turns;
}

List<TichuTurn> _generateSingles(List<Card> hand, DeckState? deck) {
  final turns = <TichuTurn>[];
  final phoenix = hand.where((card) => card.face == CardFace.phoenix).toList();
  final nonPhoenix = hand
      .where((card) => card.face != CardFace.phoenix)
      .toList();

  for (final card in nonPhoenix) {
    final turn = TichuTurn(TurnType.single, [card]);
    if (deck == null || validTurn(deck.turn, turn)) {
      turns.add(turn);
    }
  }

  if (phoenix.isNotEmpty) {
    if (deck == null) {
      turns.add(TichuTurn(TurnType.single, const [Card.phoenix(1.5)]));
    } else if (deck.turn.cards.isNotEmpty &&
        deck.turn.cards.first.face != CardFace.dragon) {
      turns.add(
        TichuTurn(TurnType.single, [Card.phoenix(deck.turn.value + 0.5)]),
      );
    }
  }

  return turns;
}

List<TichuTurn> _generatePairs(List<Card> hand, DeckState? deck) {
  final turns = <TichuTurn>[];
  final phoenixPresent = hand.any((card) => card.face == CardFace.phoenix);
  final nonPhoenix = hand
      .where((card) => card.face != CardFace.phoenix)
      .toList();
  final occurrenceCount = getOccurrenceCount(nonPhoenix);

  for (final entry in occurrenceCount.entries) {
    final face = entry.key;
    final count = entry.value;
    if (_isForbiddenPairFace(face)) {
      continue;
    }
    if (count >= 2) {
      final faceCards = nonPhoenix
          .where((card) => card.face == face)
          .toList(growable: false);
      for (var i = 0; i < faceCards.length - 1; i++) {
        for (var j = i + 1; j < faceCards.length; j++) {
          final turn = TichuTurn(TurnType.pair, [faceCards[i], faceCards[j]]);
          if (deck == null || validTurn(deck.turn, turn)) {
            turns.add(turn);
          }
        }
      }
    }
    if (phoenixPresent && count >= 1) {
      final faceCards = nonPhoenix
          .where((card) => card.face == face)
          .toList(growable: false);
      for (final card in faceCards) {
        final turn = TichuTurn(TurnType.pair, [card, Card.phoenix(card.value)]);
        if (deck == null || validTurn(deck.turn, turn)) {
          turns.add(turn);
        }
      }
    }
  }

  return turns;
}

bool _isForbiddenPairFace(CardFace face) =>
    face == CardFace.mahJong || face == CardFace.dragon || face == CardFace.dog;

List<TichuTurn> _generateTriplets(List<Card> hand, DeckState? deck) {
  final turns = <TichuTurn>[];
  final phoenixPresent = hand.any((card) => card.face == CardFace.phoenix);
  final nonPhoenix = hand
      .where((card) => card.face != CardFace.phoenix)
      .toList();
  final occurrenceCount = getOccurrenceCount(nonPhoenix);

  for (final entry in occurrenceCount.entries) {
    final face = entry.key;
    final count = entry.value;
    if (count >= 3) {
      final faceCards = nonPhoenix
          .where((card) => card.face == face)
          .toList(growable: false);
      for (var i = 0; i < faceCards.length - 2; i++) {
        for (var j = i + 1; j < faceCards.length - 1; j++) {
          for (var k = j + 1; k < faceCards.length; k++) {
            final turn = TichuTurn(TurnType.triplet, [
              faceCards[i],
              faceCards[j],
              faceCards[k],
            ]);
            if (deck == null || validTurn(deck.turn, turn)) {
              turns.add(turn);
            }
          }
        }
      }
    }
    if (phoenixPresent && count >= 2) {
      final faceCards = nonPhoenix
          .where((card) => card.face == face)
          .toList(growable: false);
      for (var i = 0; i < faceCards.length - 1; i++) {
        for (var j = i + 1; j < faceCards.length; j++) {
          final turn = TichuTurn(TurnType.triplet, [
            faceCards[i],
            faceCards[j],
            Card.phoenix(faceCards[i].value),
          ]);
          if (deck == null || validTurn(deck.turn, turn)) {
            turns.add(turn);
          }
        }
      }
    }
  }

  return turns;
}
