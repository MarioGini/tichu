/// Definition of data structs for tichu logic. Important that all non special
/// cards have index corresponding to their actual value.
enum Card {
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

// Method is essential to sort enums. This sorts in descending order.
int compareCards(Card a, Card b) {
  if (a.index == b.index) {
    return 0;
  } else if (a.index > b.index) {
    return -1;
  } else {
    return 1;
  }
}

enum Color { BLACK, GREEN, RED, BLUE }

enum TurnType {
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

// This is the input to the tichu game logic as obtained from UI.
class CardSelection {
  final Map<Card, int> cards;
  final Card wish; // can be null. If not null, cards contain mah jong.
  final int phoenixValue;

  CardSelection(this.cards, this.wish, this.phoenixValue);
}

// Describes a turn action.
class TichuTurn {
  final TurnType type;
  final Map<Card, int> cards;
  final double value;

// NOTE: The user is responsible that the type and cards do match together.
  TichuTurn(this.type, this.cards) : value = getValue(type, cards);

// The phoenix single turn is special because its value is not determined by the
// cards of the turn.
  TichuTurn.singlePhoenix(this.value)
      : type = TurnType.SINGLE,
        cards = {Card.PHOENIX: 1};

  static double getValue(TurnType type, Map<Card, int> cards) {
    switch (type) {
      case TurnType.SINGLE:
      case TurnType.DRAGON:
      case TurnType.PAIR:
      case TurnType.PAIR_STRAIGHT:
      case TurnType.STRAIGHT:
      case TurnType.TRIPLET:
      case TurnType.DOG:
        {
          List<Card> keys = cards.keys;
          keys.sort(compareCards);
          return cards.keys.first.index.toDouble();
        }
      case TurnType.BOMB:
        {
          double value;
          if (cards.length == 1) {
            // This means we have a quartet bomb.
            value = cards.keys.first.index.toDouble();
          } else {
            // This means we have a straight bomb.
            List<Card> keys = cards.keys;
            keys.sort(compareCards);
            value = 20 + cards.keys.first.index.toDouble();
          }
          return value;
        }
      case TurnType.FULL_HOUSE:
        {
          // Value of the full house is defined by value of triplet.
          return cards.keys
              .firstWhere((element) => cards[element] == 3)
              .index
              .toDouble();
        }
      default:
        return 0.0;
    }
  }
}

// Contains all information about the deck state.
class DeckState {
  final TichuTurn turn;
  final Card wish;

  DeckState(this.turn, this.wish);
}
