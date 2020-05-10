import 'package:flutter/foundation.dart';

enum CardFace {
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
  dog
}

// Special is the "color" for the four special cards of the deck.
enum Color { black, green, red, blue, special }

@immutable
class Card {
  final CardFace face;
  final Color color;
  final double value;

  Card(this.face, this.color) : value = getValue(face);

  // Play phoenix with a specific value.
  Card.phoenix(this.value)
      : face = CardFace.phoenix,
        color = Color.special;

  static double getValue(CardFace cardFace) {
    switch (cardFace) {
      case CardFace.mahJong:
        return 1.0;
      case CardFace.two:
        return 2.0;
      case CardFace.three:
        return 3.0;
      case CardFace.four:
        return 4.0;
      case CardFace.five:
        return 5.0;
      case CardFace.six:
        return 6.0;
      case CardFace.seven:
        return 7.0;
      case CardFace.eight:
        return 8.0;
      case CardFace.nine:
        return 9.0;
      case CardFace.ten:
        return 10.0;
      case CardFace.jack:
        return 11.0;
      case CardFace.queen:
        return 12.0;
      case CardFace.king:
        return 13.0;
      case CardFace.ace:
        return 14.0;
      case CardFace.dragon:
        return 25.0;
      case CardFace.phoenix:
        return -10.0;
      case CardFace.dog:
        return -2.0;
      default:
        return 0.0;
    }
  }

  @override
  bool operator ==(dynamic other) {
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
  if (a.value == b.value) {
    return 0;
  } else if (a.value > b.value) {
    return -1;
  } else {
    return 1;
  }
}

enum TurnType {
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

  static double getValue(TurnType type, List<Card> cards) {
    cards.sort(compareCards);

    switch (type) {
      case TurnType.single:
      case TurnType.pair:
      case TurnType.pairStraight:
      case TurnType.straight:
      case TurnType.triplet:
        {
          return cards.first.value;
        }
      case TurnType.bomb:
        {
          double value;
          if (cards.length == 4) {
            // This means we have a quartet bomb.
            value = cards.first.value;
          } else {
            // This means we have a straight bomb.
            value = 20 + cards.first.value; // 20 is a magic value
          }
          return value;
        }
      case TurnType.fullHouse:
        {
          var firstValueCount =
              cards.where((card) => card.value == cards.first.value).length;
          return firstValueCount == 3 ? cards.first.value : cards.last.value;
        }
      case TurnType.empty:
      case TurnType.dog:
        {
          // empty and dog have a value of 1.0 because a phoenix played on it
          // has a value of 1.5.
          return 1.0;
        }
      default:
        return 0.0;
    }
  }

  @override
  bool operator ==(dynamic other) {
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
  String currentWinner;
  List<Card> cardStack; // Contains all cards played before the current turn.

  DeckState(this.turn, this.wish);
}
