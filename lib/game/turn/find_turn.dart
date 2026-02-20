import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/card_utils.dart';
import 'package:tichu/game/turn/utils/full_house_utils.dart';
import 'package:tichu/game/turn/utils/pair_straight_utils.dart';
import 'package:tichu/game/turn/utils/straight_utils.dart';

// Returns null for invalid turns. The phoenix has already a dedicated value.
TichuTurn getTurn(final List<Card> cards) {
  TichuTurn detectedTurn;

  if (_hasUnassignedPhoenix(cards)) {
    detectedTurn = _resolvePhoenixTurn(cards);
    if (detectedTurn != TichuTurn.InvalidTurn()) {
      return detectedTurn;
    }
  }

  cards.sort(compareCards);

  if (cards.length == 1) {
    // Single card is of type single, dragon or dog.
    detectedTurn = checkSingle(cards[0]);
  } else if (cards.length == 2) {
    // Two cards can only be a pair.
    detectedTurn = checkForPair(cards);
  } else if (cards.length == 3) {
    // Three cards can only be a triplet.
    detectedTurn = checkForTriplet(cards);
  } else if (cards.length == 4) {
    // Four cards can be a quartet bomb or pair straight.
    detectedTurn = checkForQuartet(cards);
  } else if (cards.length == 5) {
    // Five cards can be a full house or a straight.
    detectedTurn = checkFives(cards);
  } else {
    // Big turns can be straights or pair straights.
    detectedTurn = checkBigTurns(cards);
  }

  return detectedTurn;
}

bool _hasUnassignedPhoenix(final List<Card> cards) => cards.any(
    (final card) =>
        card.face == CardFace.phoenix &&
        card.value == Card.getValue(CardFace.phoenix),
  );

TichuTurn _resolvePhoenixTurn(final List<Card> cards) {
  final phoenixCount = cards
      .where((final card) => card.face == CardFace.phoenix)
      .length;
  if (phoenixCount != 1) {
    return TichuTurn.InvalidTurn();
  }

  if (cards.length == 2) {
    final nonPhoenix = cards
        .where((final card) => card.face != CardFace.phoenix)
        .toList();
    if (nonPhoenix.length == 1 &&
        !_isForbiddenPairFace(nonPhoenix.first.face)) {
      final matched = _withPhoenixValue(cards, nonPhoenix.first.value);
      return TichuTurn(TurnType.pair, matched);
    }
  }

  if (cards.length == 3) {
    final nonPhoenix = cards
        .where((final card) => card.face != CardFace.phoenix)
        .toList();
    if (nonPhoenix.length == 2 && nonPhoenix[0].value == nonPhoenix[1].value) {
      final matched = _withPhoenixValue(cards, nonPhoenix[0].value);
      return TichuTurn(TurnType.triplet, matched);
    }
  }

  if (cards.length == 4) {
    final pairStraights = getPairStraights(List<Card>.from(cards), 4);
    final best = _bestTurn(pairStraights);
    if (best != null) return best;
  }

  if (cards.length == 5) {
    final fullHouses = getFullHouses(List<Card>.from(cards));
    final bestFullHouse = _bestTurn(fullHouses);
    if (bestFullHouse != null) return bestFullHouse;

    final straights = getStraights(List<Card>.from(cards), 5);
    final bestStraight = _bestTurn(straights);
    if (bestStraight != null) return bestStraight;
  }

  if (cards.length > 5) {
    final straights = getStraights(List<Card>.from(cards), cards.length);
    final bestStraight = _bestTurn(straights);
    if (bestStraight != null) return bestStraight;

    final pairStraights = getPairStraights(
      List<Card>.from(cards),
      cards.length,
    );
    final bestPairStraight = _bestTurn(pairStraights);
    if (bestPairStraight != null) return bestPairStraight;
  }

  return TichuTurn.InvalidTurn();
}

List<Card> _withPhoenixValue(final List<Card> cards, final double value) => cards
      .map((final card) => card.face == CardFace.phoenix ? Card.phoenix(value) : card)
      .toList();

TichuTurn? _bestTurn(final List<TichuTurn> turns) {
  if (turns.isEmpty) return null;
  return turns.reduce((final current, final next) => compareTurns(current, next) <= 0 ? current : next);
}

// A single card can be either of turn type dog, dragon or single.
TichuTurn checkSingle(final Card card) {
  if (card.face == CardFace.dog) {
    return TichuTurn(TurnType.dog, [card]);
  }
  return TichuTurn(TurnType.single, [card]);
}

TichuTurn checkForPair(final List<Card> cards) {
  var possibleTurn = TichuTurn.InvalidTurn();

  if (cards.length == 2 &&
      !cards.any((final card) => _isForbiddenPairFace(card.face)) &&
      (cards[0].value == cards[1].value ||
          cards.any((final card) => card.face == CardFace.phoenix))) {
    possibleTurn = TichuTurn(TurnType.pair, cards);
  }

  return possibleTurn;
}

bool _isForbiddenPairFace(final CardFace face) => face == CardFace.mahJong ||
      face == CardFace.dragon ||
      face == CardFace.dog;

TichuTurn checkForTriplet(final List<Card> cards) {
  var possibleTurn = TichuTurn.InvalidTurn();

  if (cards.length == 3 &&
      ((cards[0].value == cards[1].value && cards[1].value == cards[2].value) ||
          (cards.any((final card) => card.face == CardFace.phoenix) &&
              cards
                      .where((final card) => card.face != CardFace.phoenix)
                      .map((final card) => card.value)
                      .toSet()
                      .length ==
                  1))) {
    possibleTurn = TichuTurn(TurnType.triplet, cards);
  }

  return possibleTurn;
}

TichuTurn checkForQuartet(final List<Card> cards) {
  var possibleTurn = TichuTurn.InvalidTurn();

  if (cards.length == 4 &&
      cards.every((final element) => element.face != CardFace.phoenix) &&
      cards[0].value == cards[1].value &&
      cards[1].value == cards[2].value &&
      cards[2].value == cards[3].value) {
    // When all four cards have the same value and no phoenix is involved, we
    // have a quartet bomb.
    possibleTurn = TichuTurn(TurnType.bomb, cards);
  } else if (isPairStraight(cards)) {
    possibleTurn = TichuTurn(TurnType.pairStraight, cards);
  }

  return possibleTurn;
}

TichuTurn checkFives(final List<Card> cards) {
  var possibleTurn = TichuTurn.InvalidTurn();

  final fullHouses = getFullHouses(List<Card>.from(cards));
  if (fullHouses.isNotEmpty) {
    var best = fullHouses.first;
    for (var i = 1; i < fullHouses.length; i++) {
      if (fullHouses[i].value > best.value) {
        best = fullHouses[i];
      }
    }
    possibleTurn = best;
  } else if (isStraight(cards)) {
    if (uniformColor(cards)) {
      possibleTurn = TichuTurn(TurnType.bomb, cards);
    } else {
      possibleTurn = TichuTurn(TurnType.straight, cards);
    }
  }

  return possibleTurn;
}

// For selections with six or more cards. That can only be a straight or pair
// straight. Uniformly colored straights are bombs.
TichuTurn checkBigTurns(final List<Card> cards) {
  var possibleTurn = TichuTurn.InvalidTurn();

  if (isStraight(cards)) {
    if (uniformColor(cards)) {
      possibleTurn = TichuTurn(TurnType.bomb, cards);
    } else {
      possibleTurn = TichuTurn(TurnType.straight, cards);
    }
  } else if (isPairStraight(cards)) {
    possibleTurn = TichuTurn(TurnType.pairStraight, cards);
  }

  return possibleTurn;
}
