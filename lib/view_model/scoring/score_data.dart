import 'package:tichu/view_model/player.dart';
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
  CardFace.dog: 0
};

class Team {
  final Player firstPlayer;
  final Player secondPlayer;

  List<Card> teamCards = [];

  int score = 0;

  Team(this.firstPlayer, this.secondPlayer);
}

class ScoreCounter {
  final Team firstTeam;
  final Team secondTeam;

  List<Player> finishOrder = [];

  ScoreCounter(this.firstTeam, this.secondTeam);

  // To be called when last player finishes.
  void computeScores() {
    // Set team cards as sum of cards of the individual players.

    firstTeam.teamCards =
        firstTeam.firstPlayer.madeCards + firstTeam.secondPlayer.madeCards;
    secondTeam.teamCards =
        secondTeam.firstPlayer.madeCards + secondTeam.secondPlayer.madeCards;

    // Hand cards of last player go to the one that finished first.
    finishOrder.first.madeCards += finishOrder.last.handCards;

    // Made cards of last player go to the enemy team.
  }
}
