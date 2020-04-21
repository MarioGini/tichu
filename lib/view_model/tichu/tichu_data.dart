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

// Method is essential to sort enums.
int compareCards(Card a, Card b) {
  if (a.index == b.index) {
    return 0;
  } else if (a.index > b.index) {
    return 1;
  } else {
    return -1;
  }
}

enum Color { BLACK, GREEN, RED, BLUE }

enum TurnType {
  SINGLE,
  PAIR,
  PAIR_STRAIGHT,
  TRIPLET,
  FULL_HOUSE,
  STRAIGHT_OF_5,
  STRAIGHT_OF_6,
  STRAIGHT_OF_7,
  STRAIGHT_OF_8,
  STRAIGHT_OF_9,
  STRAIGHT_OF_10,
  STRAIGHT_OF_11,
  STRAIGHT_OF_12,
  STRAIGHT_OF_13,
  STRAIGHT_OF_14,
  DRAGON,
  DOG,
  BOMB, // Either four of a kind or a straight bomb
}

// This is the input to the tichu game logic as obtained from UI.
class CardSelection {
  final List<Card> cards;
  final Card wish; // can be null. If not null, cards contain mah jong.
  final int phoenixValue;

  CardSelection(this.cards, this.wish, this.phoenixValue);
}

// Describes a turn action.
class TichuTurn {
  final TurnType type;
  final double value;
  final List<Card> cards;

  TichuTurn(this.type, this.value, this.cards);
}

// Contains all information about the deck state.
class DeckState {
  final TichuTurn turn;
  final Card wish;

  DeckState(this.turn, this.wish);
}
