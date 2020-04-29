import 'package:tichu/view_model/tichu/tichu_data.dart';

// Core data structure for scoring.
final Map<CardFace, int> cardPoints = {
  CardFace.MAH_JONG: 0,
  CardFace.TWO: 0,
  CardFace.THREE: 0,
  CardFace.FOUR: 0,
  CardFace.FIVE: 5,
  CardFace.SIX: 0,
  CardFace.SEVEN: 0,
  CardFace.EIGHT: 0,
  CardFace.NINE: 0,
  CardFace.TEN: 10,
  CardFace.JACK: 0,
  CardFace.QUEEN: 0,
  CardFace.KING: 10,
  CardFace.ACE: 0,
  CardFace.DRAGON: 25,
  CardFace.PHOENIX: -25,
  CardFace.DOG: 0
};
