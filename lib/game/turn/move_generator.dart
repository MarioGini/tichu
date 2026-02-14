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
      break;
    case TurnType.pair:
      turns.addAll(_generatePairs(handCopy, deck));
      break;
    case TurnType.triplet:
      turns.addAll(_generateTriplets(handCopy, deck));
      break;
    case TurnType.straight:
      turns.addAll(
        getStraights(
          handCopy,
          deck.turn.cards.length,
        ).where((turn) => validTurn(deck.turn, turn)),
      );
      break;
    case TurnType.pairStraight:
      turns.addAll(
        getPairStraights(
          handCopy,
          deck.turn.cards.length,
        ).where((turn) => validTurn(deck.turn, turn)),
      );
      break;
    case TurnType.fullHouse:
      turns.addAll(
        getFullHouses(handCopy).where((turn) => validTurn(deck.turn, turn)),
      );
      break;
    case TurnType.bomb:
      turns.addAll(
        getBombs(handCopy).where((turn) => validTurn(deck.turn, turn)),
      );
      break;
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

List<TichuTurn> _generateAnyStraights(List<Card> hand) {
  final turns = <TichuTurn>[];
  final maxLength = hand.length;
  for (var length = 5; length <= maxLength; length += 1) {
    turns.addAll(getStraights(List<Card>.from(hand), length));
  }
  return turns;
}

List<TichuTurn> _generateAnyPairStraights(List<Card> hand) {
  final turns = <TichuTurn>[];
  final maxLength = hand.length;
  for (var length = 4; length <= maxLength; length += 2) {
    turns.addAll(getPairStraights(List<Card>.from(hand), length));
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
      turns.add(TichuTurn(TurnType.single, [const Card.phoenix(1.5)]));
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
