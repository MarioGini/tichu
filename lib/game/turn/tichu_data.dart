import 'package:meta/meta.dart';

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

  static double getValue(final CardFace cardFace) => switch (cardFace) {
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

  @override
  bool operator ==(final Object other) => other is Card &&
        color == other.color &&
        face == other.face &&
        value == other.value;

  @override
  int get hashCode => face.index + 5 * color.index + value.toInt() * 17;
}

// Cards are sorted based on their value. This sorts in descending order.
int compareCards(final Card a, final Card b) {
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

/// Display rank for hand ordering — specials get fixed positions so the
/// player sees them in a consistent, intuitive spot (dragon/phoenix high,
/// mahjong low, dog lowest).
int displayRank(final Card card) => switch (card.face) {
    CardFace.dragon => 1000,
    CardFace.phoenix => 900,
    CardFace.mahJong => 0,
    CardFace.dog => -100,
    _ => 100 + Card.getValue(card.face).toInt(),
  };

/// Sort comparator for hand display (descending by display rank, then color,
/// then face). Use with [List.sort].
int compareCardsForDisplay(final Card a, final Card b) {
  final rankCmp = displayRank(b).compareTo(displayRank(a));
  if (rankCmp != 0) return rankCmp;
  final colorCmp = b.color.index.compareTo(a.color.index);
  if (colorCmp != 0) return colorCmp;
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

  // ignore: non_constant_identifier_names, prefer_constructors_over_static_methods, legacy sentinel API
  static TichuTurn InvalidTurn() => TichuTurn(TurnType.none, const []);

  static double getValue(final TurnType type, final List<Card> cards) {
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
            .where((final card) => card.value == cards.first.value)
            .length;
        return firstValueCount == 3 ? cards.first.value : cards.last.value;
      }(),
      TurnType.empty || TurnType.dog => 1.0,
      TurnType.none => 0.0,
    };
  }

  @override
  bool operator ==(final Object other) {
    cards.sort(compareCards);
    if (other is TichuTurn) other.cards.sort(compareCards);

    return other is TichuTurn &&
        value == other.value &&
        type == other.type &&
        _listEquals(cards, other.cards);
  }

  @override
  int get hashCode => type.index + value.toInt() * 10;
}

bool _listEquals<T>(final List<T> a, final List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

int compareTurns(final TichuTurn a, final TichuTurn b) {
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

  // ignore: non_constant_identifier_names, prefer_constructors_over_static_methods, legacy sentinel API
  static DeckState Invalid() => DeckState(TichuTurn.InvalidTurn(), CardFace.none);
}
