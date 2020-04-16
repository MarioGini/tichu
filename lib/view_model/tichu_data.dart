/// Definition of data structs for tichu logic.

enum Card {
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
  DOG,
  MAH_JONG,
  PHOENIX
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

class TichuTurn {
  final TurnType type;
  final double value;
  int wishValue; // set to 0 when no wish is present.

  TichuTurn(this.type, this.value);
}
