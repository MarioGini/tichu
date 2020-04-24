import 'package:tichu/view_model/tichu/tichu_data.dart';

// Core data structure for scoring.
final Map<Card, int> cardPoints = {
  Card.MAH_JONG: 0,
  Card.TWO: 0,
  Card.THREE: 0,
  Card.FOUR: 0,
  Card.FIVE: 5,
  Card.SIX: 0,
  Card.SEVEN: 0,
  Card.EIGHT: 0,
  Card.NINE: 0,
  Card.TEN: 10,
  Card.JACK: 0,
  Card.QUEEN: 0,
  Card.KING: 10,
  Card.ACE: 0,
  Card.DRAGON: 25,
  Card.PHOENIX: -25,
  Card.DOG: 0
};
