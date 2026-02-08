import 'package:tichu/view_model/turn/tichu_data.dart';

// Core data structure for scoring.
final Map<CardFace, int> cardPoints = {
  CardFace.mahJong: 0,
  CardFace.two: 0,
  CardFace.three: 0,
  CardFace.four: 0,
  CardFace.five: 5,
  CardFace.six: 0,
  CardFace.seven: 0,
  CardFace.eight: 0,
  CardFace.nine: 0,
  CardFace.ten: 10,
  CardFace.jack: 0,
  CardFace.queen: 0,
  CardFace.king: 10,
  CardFace.ace: 0,
  CardFace.dragon: 25,
  CardFace.phoenix: -25,
  CardFace.dog: 0,
};

int pointsForCard(Card card) {
  return cardPoints[card.face] ?? 0;
}

int pointsForCards(Iterable<Card> cards) {
  var total = 0;
  for (final card in cards) {
    total += pointsForCard(card);
  }
  return total;
}
