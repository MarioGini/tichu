import 'package:flutter/foundation.dart';

enum CardFace {
  none,
  mahJong,
  two,
  three,
  four,
  five,
  six,
  seven,
  eight,
  nine,
  ten,
  jack,
  queen,
  king,
  ace,
  dragon,
  phoenix,
  dog,
}

// Special is the "color" for the four special cards of the deck.
enum CardColor { black, green, red, blue, special }

@immutable
class Card {
  final CardFace face;
  final CardColor color;
  final double value;

  Card(this.face, this.color) : value = getValue(face);

  // Play phoenix with a specific value.
  const Card.phoenix(this.value)
    : face = CardFace.phoenix,
      color = CardColor.special;

  static double getValue(CardFace cardFace) {
    return switch (cardFace) {
      CardFace.mahJong => 1.0,
      CardFace.two => 2.0,
      CardFace.three => 3.0,
      CardFace.four => 4.0,
      CardFace.five => 5.0,
      CardFace.six => 6.0,
      CardFace.seven => 7.0,
      CardFace.eight => 8.0,
      CardFace.nine => 9.0,
      CardFace.ten => 10.0,
      CardFace.jack => 11.0,
      CardFace.queen => 12.0,
      CardFace.king => 13.0,
      CardFace.ace => 14.0,
      CardFace.dragon => 25.0,
      CardFace.phoenix => -10.0,
      CardFace.dog => -2.0,
      CardFace.none => 0.0,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is Card &&
        color == other.color &&
        face == other.face &&
        value == other.value;
  }

  @override
  int get hashCode {
    return face.index + 5 * color.index + value.toInt() * 17;
  }
}

// Cards are sorted based on their value. This sorts in descending order.
int compareCards(Card a, Card b) {
  final valueComparison = b.value.compareTo(a.value);
  if (valueComparison != 0) {
    return valueComparison;
  }

  final colorComparison = b.color.index.compareTo(a.color.index);
  if (colorComparison != 0) {
    return colorComparison;
  }

  return b.face.index.compareTo(a.face.index);
}

enum TurnType {
  none,
  empty,
  single,
  pair,
  pairStraight, // Length of straight to be determined from number of cards.
  triplet,
  fullHouse,
  straight, // Length of straight to be determined from number of cards.
  dog,
  bomb, // Either four of a kind or a straight bomb
}

// Describes a turn action.
@immutable
class TichuTurn {
  final TurnType type;
  final List<Card> cards;
  final double value;

  // NOTE: The user is responsible that the type and cards do match together.

  TichuTurn(this.type, this.cards) : value = getValue(type, cards);

  // ignore: non_constant_identifier_names
  static TichuTurn InvalidTurn() {
    return TichuTurn(TurnType.none, []);
  }

  static double getValue(TurnType type, List<Card> cards) {
    cards.sort(compareCards);

    return switch (type) {
      TurnType.single ||
      TurnType.pair ||
      TurnType.pairStraight ||
      TurnType.straight ||
      TurnType.triplet => cards.first.value,
      TurnType.bomb =>
        cards.length == 4 ? cards.first.value : 20 + cards.first.value,
      TurnType.fullHouse => () {
        final firstValueCount = cards
            .where((card) => card.value == cards.first.value)
            .length;
        return firstValueCount == 3 ? cards.first.value : cards.last.value;
      }(),
      TurnType.empty || TurnType.dog => 1.0,
      TurnType.none => 0.0,
    };
  }

  @override
  bool operator ==(Object other) {
    cards.sort(compareCards);
    if (other is TichuTurn) other.cards.sort(compareCards);

    return other is TichuTurn &&
        value == other.value &&
        type == other.type &&
        listEquals(cards, other.cards);
  }

  @override
  int get hashCode {
    return type.index + value.toInt() * 10;
  }
}

int compareTurns(TichuTurn a, TichuTurn b) {
  if (a.value == b.value) {
    return 0;
  } else if (a.value > b.value) {
    return -1;
  } else {
    return 1;
  }
}

// Contains all information about the deck state.
class DeckState {
  final TichuTurn turn;
  final CardFace wish;
  String currentWinner = '';
  List<Card> cardStack =
      []; // Contains all cards played before the current turn.

  DeckState(this.turn, this.wish);

  // ignore: non_constant_identifier_names
  static DeckState Invalid() {
    return DeckState(TichuTurn.InvalidTurn(), CardFace.none);
  }
}
