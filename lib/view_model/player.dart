import 'turn/tichu_data.dart';
import 'turn/turn_handler.dart';

class Player {
  final String id; // ids of players at a table must be unique.
  final Player left;
  final Player partner;
  final Player right;

  List<Card> handCards;
  bool grandTichu;
  bool tichu;
  int numCards;

  int finishNumber;

  List<Card> madeCards;

  TurnHandler turnHandler;

  Player(this.id, this.left, this.partner, this.right);
}
