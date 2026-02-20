import 'package:tichu/game/turn/tichu_data.dart';

/// Point values per card face. Only non-zero entries listed.
const Map<CardFace, int> cardPoints = {
  CardFace.five: 5,
  CardFace.ten: 10,
  CardFace.king: 10,
  CardFace.dragon: 25,
  CardFace.phoenix: -25,
};

int pointsForCard(final Card card) => cardPoints[card.face] ?? 0;

int pointsForCards(final Iterable<Card> cards) {
  var total = 0;
  for (final c in cards) {
    total += cardPoints[c.face] ?? 0;
  }
  return total;
}
