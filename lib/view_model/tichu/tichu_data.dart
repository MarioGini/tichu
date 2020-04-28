/// Definition of data structs for tichu logic.

enum CardFace {
  MAH_JONG,
  TWO,
  THREE,
  FOUR,
  FIVE,
  SIX,
  SEVEN,
  EIGHT,
  NINE,
  TEN,
  JACK,
  QUEEN,
  KING,
  ACE,
  DRAGON,
  PHOENIX,
  DOG
}

// Special is the "color" for the four special cards of the deck.
enum Color { BLACK, GREEN, RED, BLUE, SPECIAL }

class Card {
  final CardFace face;
  final Color color;
  final double value;

  Card(CardFace cardFace, Color color)
      : face = cardFace,
        color = color,
        value = getValue(cardFace);

// Play phoenix with a specific value.
  Card.phoenix(double value)
      : face = CardFace.PHOENIX,
        color = Color.SPECIAL,
        value = value;

  static double getValue(CardFace cardFace) {
    switch (cardFace) {
      case CardFace.MAH_JONG:
        return 1.0;
      case CardFace.TWO:
        return 2.0;
      case CardFace.THREE:
        return 3.0;
      case CardFace.FOUR:
        return 4.0;
      case CardFace.FIVE:
        return 5.0;
      case CardFace.SIX:
        return 6.0;
      case CardFace.SEVEN:
        return 7.0;
      case CardFace.EIGHT:
        return 8.0;
      case CardFace.NINE:
        return 9.0;
      case CardFace.TEN:
        return 10.0;
      case CardFace.JACK:
        return 11.0;
      case CardFace.QUEEN:
        return 12.0;
      case CardFace.KING:
        return 13.0;
      case CardFace.ACE:
        return 14.0;
      case CardFace.DRAGON:
        return 15.0;
      case CardFace.PHOENIX:
        return -1.0;
      case CardFace.DOG:
        return 0.0;
      default:
        return 0.0;
    }
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
  EMPTY,
  SINGLE,
  PAIR,
  PAIR_STRAIGHT, // Length of straight to be determined from number of cards.
  TRIPLET,
  FULL_HOUSE,
  STRAIGHT, // Length of straight to be determined from number of cards.
  DRAGON,
  DOG,
  BOMB, // Either four of a kind or a straight bomb
}

// Describes a turn action.
class TichuTurn {
  final TurnType type;
  final List<Card> cards;
  final double value;

// NOTE: The user is responsible that the type and cards do match together.
  TichuTurn(TurnType type, List<Card> cards)
      : type = type,
        cards = cards,
        value = getValue(type, cards);

  static double getValue(TurnType type, List<Card> cards) {
    switch (type) {
      case TurnType.SINGLE:
      case TurnType.DRAGON:
      case TurnType.PAIR:
      case TurnType.PAIR_STRAIGHT:
      case TurnType.STRAIGHT:
      case TurnType.TRIPLET:
      case TurnType.DOG:
        {
          cards.sort(compareCards);
          return cards.first.value;
        }
      case TurnType.BOMB:
        {
          double value;
          if (cards.length == 1) {
            // This means we have a quartet bomb.
            value = cards.first.value;
          } else {
            // This means we have a straight bomb.
            cards.sort(compareCards);
            value = 20 + cards.first.value;
          }
          return value;
        }
      case TurnType.FULL_HOUSE:
        {
          // Value of the full house is defined by value of triplet.
          return 0.0;
        }
      case TurnType.EMPTY:
        {
          // empty has a value of 1.0 because a phoenix played on it has a value
          // of 1.5.
          return 1.0;
        }
      default:
        return 0.0;
    }
  }
}

// Contains all information about the deck state.
class DeckState {
  final TichuTurn turn;
  final CardFace wish;

  DeckState(this.turn, this.wish);
}

// TODO environment class that stores tichu calls and scores.
